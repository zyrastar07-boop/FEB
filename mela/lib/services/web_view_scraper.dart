import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// One discovered media URL (HLS / MP4 / WebM).
class StreamVariant {
  final String url;
  final int? height;
  final int? bitrate;
  final String format;

  StreamVariant({
    required this.url,
    this.height,
    this.bitrate,
    required this.format,
  });
}

/// Result handed back when extraction succeeds.
class ExtractedStreamData {
  final String bestUrl;
  final List<StreamVariant> allStreams;
  final bool isWebM;

  ExtractedStreamData({
    required this.bestUrl,
    required this.allStreams,
    this.isWebM = false,
  });
}

/// Off-screen (or visible) WebView that opens an embed player page and
/// intercepts network / DOM activity to find a direct stream URL.
class WebViewScraper extends StatefulWidget {
  final String embedUrl;
  final String mediaType; // 'movie' | 'tv'
  final int? season;
  final int? episode;
  final ValueChanged<ExtractedStreamData> onDataExtracted;
  final ValueChanged<String>? onError;
  final ValueChanged<bool>? onLoading;
  final int timeoutSeconds;
  final bool debug;

  const WebViewScraper({
    super.key,
    required this.embedUrl,
    required this.onDataExtracted,
    this.onError,
    this.onLoading,
    this.mediaType = 'movie',
    this.season,
    this.episode,
    this.timeoutSeconds = 10,
    this.debug = false,
  });

  @override
  State<WebViewScraper> createState() => _WebViewScraperState();
}

class _WebViewScraperState extends State<WebViewScraper> {
  final List<StreamVariant> _candidates = [];
  final Set<String> _seenUrls = {};
  final Set<String> _visitedPages = {};
  final List<String> _iframeQueue = [];

  bool _finished = false;
  int _retryCount = 0;
  int _iframeIndex = 0;

  Timer? _finalizeTimer;
  InAppWebViewController? _controller;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  bool get _isTv => widget.mediaType.toLowerCase() == 'tv';

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    super.dispose();
  }

  bool _isMediaUrl(String url) {
    final u = url.toLowerCase();
    if (u.startsWith('blob:')) return false;
    return u.contains('.m3u8') ||
        u.contains('.mp4') ||
        u.contains('.webm') ||
        u.contains('.mkv') ||
        u.contains('/hls/') ||
        u.contains('googlevideo') ||
        u.contains('videoplayback');
  }

  bool _isPlayerFrame(String url) {
    final u = url.toLowerCase();
    if (_isMediaUrl(url)) return false;
    if (!u.startsWith('http')) return false;
    // Skip ads / trackers
    if (u.contains('doubleclick') ||
        u.contains('googlesyndication') ||
        u.contains('facebook') ||
        u.contains('analytics') ||
        u.contains('adservice')) {
      return false;
    }
    return u.contains('embed') ||
        u.contains('player') ||
        u.contains('vidfast') ||
        u.contains('videasy') ||
        u.contains('cinesrc') ||
        u.contains('cineplay') ||
        u.contains('vidsrc') ||
        u.contains('vidlink') ||
        u.contains('superembed') ||
        u.contains('autoembed') ||
        u.contains('episode') ||
        u.contains('series') ||
        u.contains('/tv/') ||
        u.contains('/movie/');
  }

  String _detectFormat(String url) {
    final u = url.toLowerCase();
    if (u.contains('.m3u8') || u.contains('/hls/')) return 'hls';
    if (u.contains('.mp4') || u.contains('videoplayback') || u.contains('googlevideo')) {
      return 'mp4';
    }
    if (u.contains('.webm')) return 'webm';
    if (u.contains('.mkv')) return 'mkv';
    return 'unknown';
  }

  void _addCandidate(Map data) {
    if (_finished) return;
    final raw = data['url']?.toString();
    if (raw == null || raw.isEmpty) return;

    String url = raw;
    try {
      url = Uri.decodeFull(url);
    } catch (_) {}
    url = url.split('#').first;

    if (!_isMediaUrl(url)) {
      if (_isPlayerFrame(url) &&
          !_visitedPages.contains(url) &&
          !_iframeQueue.contains(url)) {
        _iframeQueue.add(url);
        debugPrint('[WebViewScraper] queued iframe: $url');
      }
      return;
    }

    if (!_seenUrls.add(url)) return;

    final format = _detectFormat(url);
    _candidates.add(
      StreamVariant(
        url: url,
        height: data['height'] is int ? data['height'] as int : null,
        bitrate: data['bitrate'] is int ? data['bitrate'] as int : null,
        format: format,
      ),
    );

    debugPrint('[WebViewScraper] candidate ($format): $url');

    if (format == 'hls' || format == 'mp4' || format == 'webm') {
      _finalize(early: true);
    }
  }

  int _score(StreamVariant s) {
    var score = 0;
    switch (s.format) {
      case 'hls':
        score += 1000;
        break;
      case 'mp4':
        score += 600;
        break;
      case 'webm':
        score += 400;
        break;
      case 'mkv':
        score += 500;
        break;
    }
    if (s.height != null) score += s.height! * 5;
    if (s.bitrate != null) score += s.bitrate! ~/ 1000;
    return score;
  }

  StreamVariant _rankBest() {
    final list = List<StreamVariant>.from(_candidates)
      ..sort((a, b) => _score(b).compareTo(_score(a)));
    return list.first;
  }

  void _finalize({bool early = false}) {
    if (_finished) return;

    if (_candidates.isEmpty) {
      while (_iframeIndex < _iframeQueue.length) {
        final next = _iframeQueue[_iframeIndex++];
        if (!_visitedPages.contains(next)) {
          _visitedPages.add(next);
          debugPrint('[WebViewScraper] opening iframe player: $next');
          _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(next)));
          _armFinalizeTimer();
          return;
        }
      }

      if (_retryCount < 1) {
        _retryCount++;
        debugPrint('[WebViewScraper] soft retry $_retryCount');
        _controller?.reload();
        _armFinalizeTimer();
        return;
      }

      _finished = true;
      widget.onLoading?.call(false);
      widget.onError?.call(
        _isTv
            ? 'No stream found for this episode. Ensure season/episode parameters are in the embed URL.'
            : 'No streams found',
      );
      return;
    }

    _finished = true;
    _finalizeTimer?.cancel();
    widget.onLoading?.call(false);

    final best = _rankBest();
    debugPrint(
      '[WebViewScraper] ${early ? "early" : "final"} best=${best.format} ${best.url}',
    );

    widget.onDataExtracted(
      ExtractedStreamData(
        bestUrl: best.url,
        allStreams: List.unmodifiable(_candidates),
        isWebM: best.format == 'webm',
      ),
    );
  }

  void _armFinalizeTimer() {
    _finalizeTimer?.cancel();
    final secs = widget.timeoutSeconds.clamp(5, 30);
    _finalizeTimer = Timer(Duration(seconds: secs), () => _finalize());
  }

  String _injectJS() {
    return r'''
(function() {
  if (window.__melaScraperHooked) return;
  window.__melaScraperHooked = true;

  function send(obj) {
    try {
      window.flutter_inappwebview.callHandler('stream', JSON.stringify(obj));
    } catch (e) {}
  }

  function fastMatch(url) {
    if (!url || typeof url !== 'string') return false;
    var u = url.toLowerCase();
    return u.indexOf('m3u8') !== -1
      || u.indexOf('.mp4') !== -1
      || u.indexOf('.webm') !== -1
      || u.indexOf('.mkv') !== -1
      || u.indexOf('/hls/') !== -1
      || u.indexOf('googlevideo') !== -1
      || u.indexOf('videoplayback') !== -1;
  }

  function isPlayerFrame(url) {
    if (!url || typeof url !== 'string') return false;
    var u = url.toLowerCase();
    if (fastMatch(u)) return false;
    if (u.indexOf('http') !== 0) return false;
    if (u.indexOf('doubleclick') !== -1 || u.indexOf('analytics') !== -1 || u.indexOf('adservice') !== -1) return false;
    return u.indexOf('embed') !== -1
      || u.indexOf('player') !== -1
      || u.indexOf('vidfast') !== -1
      || u.indexOf('videasy') !== -1
      || u.indexOf('cinesrc') !== -1
      || u.indexOf('cineplay') !== -1
      || u.indexOf('vidsrc') !== -1
      || u.indexOf('vidlink') !== -1
      || u.indexOf('superembed') !== -1
      || u.indexOf('autoembed') !== -1
      || u.indexOf('episode') !== -1
      || u.indexOf('series') !== -1
      || u.indexOf('/tv/') !== -1
      || u.indexOf('/movie/') !== -1;
  }

  function report(url, kind) {
    if (!url || typeof url !== 'string') return;
    try { url = decodeURIComponent(url); } catch (e) {}
    url = url.split('#')[0];
    if (url.indexOf('blob:') === 0) return;

    if (fastMatch(url)) {
      send({ type: 'video', url: url });
      return;
    }
    if (kind === 'iframe' && isPlayerFrame(url)) {
      send({ type: 'iframe', url: url });
    }
  }

  // --- XHR ---
  try {
    var oOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      try { report(String(url), 'xhr'); } catch (e) {}
      this.addEventListener('load', function() {
        try { report(this.responseURL, 'xhr'); } catch (e) {}
      });
      return oOpen.apply(this, arguments);
    };
  } catch (e) {}

  // --- fetch ---
  try {
    var oFetch = window.fetch;
    window.fetch = function(input, init) {
      try {
        var u = typeof input === 'string' ? input : (input && input.url);
        report(String(u), 'fetch');
      } catch (e) {}
      return oFetch.apply(this, arguments).then(function(res) {
        try { report(res.url, 'fetch'); } catch (e) {}
        return res;
      });
    };
  } catch (e) {}

  // --- video / source tags ---
  function scanVideo() {
    try {
      document.querySelectorAll('video, source').forEach(function(v) {
        if (v.src) report(v.src, 'dom');
        if (v.currentSrc) report(v.currentSrc, 'dom');
      });
    } catch (e) {}
  }
  setInterval(scanVideo, 1200);

  // --- performance resource timing ---
  function scanPerf() {
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var i = 0; i < entries.length; i++) {
        report(entries[i].name || '', 'perf');
      }
    } catch (e) {}
  }
  setInterval(scanPerf, 1800);

  // --- iframes ---
  function scanIframes() {
    try {
      document.querySelectorAll('iframe').forEach(function(f) {
        if (f.src) report(f.src, 'iframe');
      });
    } catch (e) {}
  }
  setInterval(scanIframes, 1500);

  // --- HTML regex fallback ---
  function scanHtml() {
    try {
      var html = document.documentElement && document.documentElement.innerHTML;
      if (!html) return;
      var re = /(https?:\/\/[^\s"'<>\\]+?(?:\.m3u8|\.mp4|\.webm)(?:\?[^\s"'<>\\]*)?)/gi;
      var m;
      while ((m = re.exec(html)) !== null) report(m[1], 'html');
    } catch (e) {}
  }
  setTimeout(scanHtml, 2500);
  setTimeout(scanHtml, 5000);

  // --- try autoplay ---
  setTimeout(function() {
    try {
      document.querySelectorAll('video').forEach(function(v) {
        v.muted = true;
        v.play().catch(function() {});
      });
      var btns = document.querySelectorAll('button, [role=button], .play, .play-btn, #play, .vjs-big-play-button');
      for (var i = 0; i < btns.length; i++) {
        var t = ((btns[i].innerText || '') + ' ' + (btns[i].className || '')).toLowerCase();
        if (t.indexOf('play') !== -1) {
          try { btns[i].click(); } catch (e) {}
        }
      }
    } catch (e) {}
  }, 800);

  send({ type: 'log', url: 'hook-installed:' + location.href });
})();
true;
''';
  }

  @override
  Widget build(BuildContext context) {
    final child = InAppWebView(
      key: ValueKey(widget.embedUrl),
      initialUrlRequest: URLRequest(url: WebUri(widget.embedUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        userAgent: _ua,
        thirdPartyCookiesEnabled: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        _visitedPages.add(widget.embedUrl);
        widget.onLoading?.call(true);

        controller.addJavaScriptHandler(
          handlerName: 'stream',
          callback: (args) {
            if (_finished || args.isEmpty) return null;
            try {
              final raw = args.first;
              final decoded = raw is String ? jsonDecode(raw) : raw;
              if (decoded is! Map) return null;
              final map = Map<String, dynamic>.from(decoded);

              final type = map['type']?.toString() ?? 'video';
              if (type == 'log') {
                debugPrint('[WebViewScraper] ${map['url']}');
                return null;
              }

              final url = map['url']?.toString() ?? map['responseURL']?.toString();
              if (url == null) return null;

              if (type == 'iframe') {
                _addCandidate({'url': url});
              } else {
                _addCandidate({'url': url, 'height': map['height'], 'bitrate': map['bitrate']});
              }
            } catch (e) {
              debugPrint('[WebViewScraper] handler error: $e');
            }
            return null;
          },
        );
      },
      onLoadStart: (controller, url) {
        debugPrint('[WebViewScraper] load start: $url');
      },
      onLoadStop: (controller, url) async {
        debugPrint('[WebViewScraper] load stop: $url');
        try {
          await controller.evaluateJavascript(source: _injectJS());
        } catch (e) {
          debugPrint('[WebViewScraper] inject failed: $e');
        }
        _armFinalizeTimer();
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          '[WebViewScraper] error: ${error.type} ${error.description}',
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        if (_isMediaUrl(url)) {
          _addCandidate({'url': url});
        }
        return NavigationActionPolicy.ALLOW;
      },
    );

    if (widget.debug) {
      return SizedBox(width: 360, height: 240, child: child);
    }

    // Fixed: Fully hide the scraper view behind UI without breaking DOM/Network hooks
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: child,
      ),
    );
  }
}