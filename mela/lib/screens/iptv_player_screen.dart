import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/iptv_channel_model.dart';

/// Full-screen high-performance IPTV player with glassmorphism controls,
/// gesture support and auto-retry resilience.
class IptvPlayerScreen extends StatefulWidget {
  final IptvChannel channel;
  final List<IptvChannel> allChannels;
  final ValueChanged<IptvChannel>? onChannelChanged;

  const IptvPlayerScreen({
    super.key,
    required this.channel,
    required this.allChannels,
    this.onChannelChanged,
  });

  @override
  State<IptvPlayerScreen> createState() => _IptvPlayerScreenState();
}

class _IptvPlayerScreenState extends State<IptvPlayerScreen>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  late IptvChannel _currentChannel;

  bool _initialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isBuffering = true;
  bool _hasError = false;
  String? _errorMessage;
  int _retryCount = 0;
  static const int _maxRetries = 4;

  Timer? _hideControlsTimer;
  Timer? _retryTimer;

  // Gesture tracking
  double _volume = 1.0;
  double? _dragStartY;
  double? _dragStartX;
  bool _isHorizontalDrag = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentChannel = widget.channel;
    // Keep the screen awake while watching live TV
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    _initPlayer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _retryTimer?.cancel();
    _controller.dispose();
    // Allow the screen to sleep again when leaving the player
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller.pause();
      // Optional: release wakelock while app is in background
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      // Re-enable wakelock when user returns to the player
      WakelockPlus.enable();
      if (_isPlaying) {
        _controller.play();
      }
    }
  }

  Future<void> _initPlayer() async {
    setState(() {
      _initialized = false;
      _isBuffering = true;
      _hasError = false;
      _errorMessage = null;
    });

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(_currentChannel.streamUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      },
    );

    try {
      await _controller.initialize().timeout(const Duration(seconds: 12));
      _controller.addListener(_playerListener);
      await _controller.play();
      if (mounted) {
        setState(() {
          _initialized = true;
          _isPlaying = true;
          _isBuffering = false;
          _retryCount = 0;
        });
        _scheduleHideControls();
      }
    } catch (e) {
      if (mounted) _handleError(e.toString());
    }
  }

  void _playerListener() {
    if (!mounted) return;
    final value = _controller.value;

    final buffering = value.isBuffering;
    if (buffering != _isBuffering) {
      setState(() => _isBuffering = buffering);
    }

    if (value.hasError) {
      _handleError(value.errorDescription ?? 'Playback error');
    }
  }

  void _handleError(String message) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      setState(() {
        _hasError = true;
        _errorMessage = 'Connection issue – retrying ($_retryCount/$_maxRetries)…';
        _isBuffering = true;
      });
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: 1 + _retryCount), () {
        if (mounted) {
          _controller.dispose();
          _initPlayer();
        }
      });
    } else {
      setState(() {
        _hasError = true;
        _errorMessage = message;
        _isBuffering = false;
      });
    }
  }

  void _togglePlayPause() {
    if (!_initialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _isPlaying = false);
    } else {
      _controller.play();
      setState(() => _isPlaying = true);
    }
    _scheduleHideControls();
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_hasError) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  void _switchChannel(IptvChannel newChannel) {
    if (newChannel.id == _currentChannel.id) return;
    setState(() {
      _currentChannel = newChannel;
      _retryCount = 0;
    });
    widget.onChannelChanged?.call(newChannel);
    _controller.dispose();
    _initPlayer();
  }

  void _nextChannel() {
    final idx = widget.allChannels
        .indexWhere((c) => c.id == _currentChannel.id);
    if (idx == -1 || widget.allChannels.length < 2) return;
    final next = widget.allChannels[(idx + 1) % widget.allChannels.length];
    _switchChannel(next);
  }

  void _previousChannel() {
    final idx = widget.allChannels
        .indexWhere((c) => c.id == _currentChannel.id);
    if (idx == -1 || widget.allChannels.length < 2) return;
    final prev = widget.allChannels[
        (idx - 1 + widget.allChannels.length) % widget.allChannels.length];
    _switchChannel(prev);
  }

  void _openChannelDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.55,
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Quick Switch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.allChannels.length,
                  itemBuilder: (_, i) {
                    final ch = widget.allChannels[i];
                    final selected = ch.id == _currentChannel.id;
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF2A2A2A),
                        backgroundImage: ch.logoUrl != null
                            ? CachedNetworkImageProvider(ch.logoUrl!)
                            : null,
                        child: ch.logoUrl == null
                            ? const Icon(Icons.live_tv, size: 18, color: Colors.white38)
                            : null,
                      ),
                      title: Text(
                        ch.name,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFFFFB800)
                              : Colors.white,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        ch.groupTitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.play_circle_fill,
                              color: Color(0xFFFFB800))
                          : Text(
                              ch.quality,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchChannel(ch);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Gesture handlers ─────────────────────────────────────────────────────

  void _onVerticalDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_dragStartY == null) return;
    final delta = _dragStartY! - d.globalPosition.dy;
    // Simple volume gesture (left half of screen) – real brightness needs platform channels
    final newVol = (_volume + delta / 300).clamp(0.0, 1.0);
    if ((newVol - _volume).abs() > 0.02) {
      _volume = newVol;
      _controller.setVolume(_volume);
      setState(() {});
    }
    _dragStartY = d.globalPosition.dy;
  }

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartX = d.globalPosition.dx;
    _isHorizontalDrag = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_dragStartX == null) return;
    final delta = d.globalPosition.dx - _dragStartX!;
    if (delta.abs() > 40) _isHorizontalDrag = true;
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (!_isHorizontalDrag || _dragStartX == null) return;
    final delta = d.primaryVelocity ?? 0;
    if (delta < -400) {
      _nextChannel();
    } else if (delta > 400) {
      _previousChannel();
    }
    _dragStartX = null;
    _isHorizontalDrag = false;
  }

  void _onDoubleTapDown(TapDownDetails d) {
    final width = MediaQuery.of(context).size.width;
    if (d.globalPosition.dx < width * 0.35) {
      // Left side – previous channel (or seek if VOD)
      _previousChannel();
    } else if (d.globalPosition.dx > width * 0.65) {
      _nextChannel();
    } else {
      _togglePlayPause();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: _onDoubleTapDown,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (_initialized && !_hasError)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio == 0
                      ? 16 / 9
                      : _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              Container(color: Colors.black),

            // Buffering spinner
            if (_isBuffering && !_hasError)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.8,
                      color: Color(0xFFFFB800),
                    ),
                  ),
                ),
              ),

            // Error overlay
            if (_hasError && _retryCount >= _maxRetries)
              _buildErrorOverlay(),

            // Controls
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _buildControlsOverlay(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.65),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.75),
          ],
          stops: const [0.0, 0.25, 0.65, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  // Logo
                  if (_currentChannel.logoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: _currentChannel.logoUrl!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentChannel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _currentChannel.groupTitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            const Color(0xFFFFB800).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _currentChannel.quality,
                      style: const TextStyle(
                        color: Color(0xFFFFB800),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Center play button
            if (!_isBuffering)
              IconButton(
                iconSize: 64,
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                onPressed: _togglePlayPause,
              ),

            const Spacer(),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded,
                        color: Colors.white70, size: 28),
                    onPressed: _previousChannel,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded,
                        color: Colors.white70, size: 28),
                    onPressed: _nextChannel,
                  ),
                  const Spacer(),
                  // Volume indicator (simple)
                  Icon(
                    _volume <= 0.01
                        ? Icons.volume_off_rounded
                        : _volume < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.list_rounded,
                        color: Colors.white, size: 26),
                    onPressed: _openChannelDrawer,
                    tooltip: 'Channel list',
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded,
                        color: Colors.white, size: 26),
                    onPressed: () {
                      // Toggle orientation as a simple fullscreen proxy
                      final isLandscape =
                          MediaQuery.of(context).orientation ==
                              Orientation.landscape;
                      SystemChrome.setPreferredOrientations(
                        isLandscape
                            ? [DeviceOrientation.portraitUp]
                            : [
                                DeviceOrientation.landscapeLeft,
                                DeviceOrientation.landscapeRight,
                              ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.white38, size: 52),
            const SizedBox(height: 16),
            Text(
              'Unable to play this stream',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () {
                    _retryCount = 0;
                    _controller.dispose();
                    _initPlayer();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB800),
                    backgroundColor:
                        const Color(0xFFFFB800).withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _nextChannel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Next Channel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}