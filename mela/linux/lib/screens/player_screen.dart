import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/font_service.dart';

const _gold = Color(0xFFFFB800);

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String serverName;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.serverName,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showControls = true;
  bool _isLocked = false;
  String? _errorMessage;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('Player error: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.streamUrl));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openInExternalBrowser() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(widget.streamUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _retry() {
    HapticFeedback.mediumImpact();
    setState(() {
      _hasError = false;
      _isLoading = true;
      _errorMessage = null;
    });
    _controller.loadRequest(Uri.parse(widget.streamUrl));
  }

  void _toggleControls() {
    if (_isLocked) return;
    HapticFeedback.selectionClick();
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _fadeCtrl.forward();
    } else {
      _fadeCtrl.reverse();
    }
  }

  void _toggleLock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _showControls = false;
        _fadeCtrl.reverse();
      } else {
        _showControls = true;
        _fadeCtrl.forward();
      }
    });
  }

  void _reload() {
    HapticFeedback.selectionClick();
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video WebView
            WebViewWidget(controller: _controller),

            // Loading overlay
            if (_isLoading && !_hasError)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          color: _gold,
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connecting to ${widget.serverName}…',
                        style: FontService.instance.label(
                          color: Colors.white70,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FontService.instance.style(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Error overlay
            if (_hasError)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Playback failed',
                          style: FontService.instance.display(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage ??
                              'Could not load stream from ${widget.serverName}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _actionChip(
                              icon: Icons.refresh_rounded,
                              label: 'Retry',
                              onTap: _retry,
                              filled: true,
                            ),
                            const SizedBox(width: 12),
                            _actionChip(
                              icon: Icons.open_in_browser_rounded,
                              label: 'Open in browser',
                              onTap: _openInExternalBrowser,
                            ),
                            const SizedBox(width: 12),
                            _actionChip(
                              icon: Icons.arrow_back_rounded,
                              label: 'Back',
                              onTap: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Top controls bar (fade)
            if (!_hasError)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 16,
                        right: 16,
                        bottom: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          _circleBtn(
                            Icons.arrow_back_rounded,
                            () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _gold.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      widget.serverName.toUpperCase(),
                                      style: FontService.instance.label(
                                        color: _gold,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FontService.instance.style(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _circleBtn(Icons.refresh_rounded, _reload),
                          const SizedBox(width: 8),
                          _circleBtn(
                            Icons.open_in_browser_rounded,
                            _openInExternalBrowser,
                            gold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom controls (lock + tips)
            if (!_hasError)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Container(
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: MediaQuery.of(context).padding.bottom + 14,
                        top: 20,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          _bottomChip(
                            icon: _isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            label: _isLocked ? 'Locked' : 'Lock',
                            onTap: _toggleLock,
                            active: _isLocked,
                          ),
                          const Spacer(),
                          Text(
                            'Tap to show / hide controls',
                            style: FontService.instance.label(
                              color: Colors.white38,
                              fontSize: 11,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const Spacer(),
                          _bottomChip(
                            icon: Icons.screen_rotation_rounded,
                            label: 'Rotate',
                            onTap: () {
                              HapticFeedback.selectionClick();
                              // System already forces landscape; this is visual feedback
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Lock indicator when locked
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
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _gold.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_rounded,
                            color: _gold, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Tap to unlock',
                          style: FontService.instance.label(
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
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {bool gold = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(
            color: gold
                ? _gold.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Icon(icon,
            color: gold ? _gold : Colors.white, size: 18),
      ),
    );
  }

  Widget _bottomChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? _gold.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? _gold.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? _gold : Colors.white70, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: FontService.instance.label(
                color: active ? _gold : Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? _gold : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: filled ? Colors.black : Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}