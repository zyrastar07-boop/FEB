import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

/// One discovered media URL (HLS / MP4 / WebM) with accurate resolution.
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

/// Off-screen WebView that opens an embed page and intercepts network/DOM
/// activity to find direct stream URLs.
///
/// Hardening + speed + unstable-network + 4K:
/// - Parallel top‑N probing with short timeouts
/// - Parses real HLS master playlists for accurate resolution/bitrate
/// - Scores 4K/2160p highest when present; prefers validated HLS
/// - Caches resolved entries in a process‑lifetime LRU map
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
    this.timeoutSeconds = 14,
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
  final Set<String> _validatedOk = {};
  final Set<String> _validatedBad = {};

  bool _finished = false;
  bool _validating = false;
  int _retryCount = 0;
  int _iframeIndex = 0;

  Timer? _finalizeTimer;
  Timer? _earlyCheckTimer;
  InAppWebViewController? _controller;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  bool get _isTv => widget.mediaType.toLowerCase() == 'tv';

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    _earlyCheckTimer?.cancel();
    super.dispose();
  }

  bool _isMediaUrl(String url) {
    final u = url.toLowerCase();
    if (u.startsWith('blob:') || u.startsWith('data:')) return false;
    return u.contains('.m3u8') ||
        u.contains('.mp4') ||
        u.contains('.webm') ||
        u.contains('.mkv') ||
        u.contains('/hls/') ||
        u.contains('googlevideo') ||
        u.contains('videoplayback') ||
        u.contains('manifest') ||
        u.contains('playlist');
  }

  bool _isPlayerFrame(String url) {
    final u = url.toLowerCase();
    if (_isMediaUrl(url)) return false;
    if (!u.startsWith('http')) return false;
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
        u.contains('vixsrc') ||
        u.contains('vidsrc') ||
        u.contains('vidlink') ||
        u.contains('superembed') ||
        u.contains('autoembed') ||
        u.contains('multiembed') ||
        u.contains('2embed') ||
        u.contains('embed.su') ||
        u.contains('moviesapi') ||
        u.contains('episode') ||
        u.contains('series') ||
        u.contains('/tv/') ||
        u.contains('/movie/') ||
        u.contains('rivestream') ||
        u.contains('moviesjoy') ||
        u.contains('fmovies');
  }

  String _detectFormat(String url) {
    final u = url.toLowerCase();
    if (u.contains('.m3u8') || u.contains('/hls/') || u.contains('mpegurl')) {
      return 'hls';
    }
    if (u.contains('.mp4') ||
        u.contains('videoplayback') ||
        u.contains('googlevideo')) {
      return 'mp4';
    }
    if (u.contains('.webm')) return 'webm';
    if (u.contains('.mkv')) return 'mkv';
    return 'unknown';
  }

  /// Guess height from common CDN URL tokens (4K / 1080 / 720 …).
  int? _guessHeight(String url) {
    final u = url.toLowerCase();
    final patterns = <RegExp, int>{
      RegExp(r'(?:^|[^\d])(2160|4k|uhd)(?:[^\d]|$)'): 2160,
      RegExp(r'(?:^|[^\d])(1440|2k)(?:[^\d]|$)'): 1440,
      RegExp(r'(?:^|[^\d])(1080|fhd)(?:[^\d]|$)'): 1080,
      RegExp(r'(?:^|[^\d])(720|hd)(?:[^\d]|$)'): 720,
      RegExp(r'(?:^|[^\d])(480|sd)(?:[^\d]|$)'): 480,
      RegExp(r'(?:^|[^\d])(360)(?:[^\d]|$)'): 360,
    };
    for (final e in patterns.entries) {
      if (e.key.hasMatch(u)) return e.value;
    }
    return null;
  }

  void _addCandidate(Map data) {
    if (_finished) return;
    final raw = data['url']?.toString();
    if (raw == null || raw.isEmpty) return;

    String url = raw;
    try {
      url = Uri.decodeFull(url);
    } catch (_) {}
    url = url.split('#').first.trim();

    if (!_isMediaUrl(url)) {
      if (_isPlayerFrame(url) &&
          !_visitedPages.contains(url) &&
          !_iframeQueue.contains(url)) {
        _iframeQueue.add(url);
      }
      return;
    }

    if (_validatedBad.contains(url)) return;
    if (!_seenUrls.add(url)) return;

    final format = _detectFormat(url);
    int? height = data['height'] is int ? data['height'] as int : null;
    height ??= _guessHeight(url);

    _candidates.add(
      StreamVariant(
        url: url,
        height: height,
        bitrate: data['bitrate'] is int ? data['bitrate'] as int : null,
        format: format,
      ),
    );

    // Early check – faster window, still probes before emit.
    _earlyCheckTimer?.cancel();
    _earlyCheckTimer = Timer(const Duration(milliseconds: 420), () {
      if (!_finished && _candidates.isNotEmpty) {
        unawaited(_tryFinalizeValidated(early: true));
      }
    });
  }

  /// Prefer validated HLS, then 4K > 1080 > 720.
  int _score(StreamVariant s) {
    var score = 0;
    switch (s.format) {
      case 'hls':
        score += 1200;
        break;
      case 'mp4':
        score += 700;
        break;
      case 'mkv':
        score += 550;
        break;
      case 'webm':
        score += 450;
        break;
    }
    if (s.height != null) {
      final h = s.height!;
      if (h >= 2160) {
        score += 2500;
      } else if (h >= 1440) {
        score += 1800;
      } else if (h >= 1080) {
        score += 1400;
      } else if (h >= 720) {
        score += 900;
      } else if (h >= 480) {
        score += 400;
      } else {
        score += h;
      }
    }
    if (s.bitrate != null) score += (s.bitrate! ~/ 800).clamp(0, 800);
    if (_validatedOk.contains(s.url)) score += 3000;
    return score;
  }

  /// HEAD / ranged‑GET probe optimised for slow & unstable links.
  Future<bool> _probeUrl(String mediaUrl) async {
    if (_validatedOk.contains(mediaUrl)) return true;
    if (_validatedBad.contains(mediaUrl)) return false;

    try {
      final uri = Uri.parse(mediaUrl);
      final headers = <String, String>{
        'User-Agent': _ua,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
        'Referer': widget.embedUrl,
      };
      try {
        final emb = Uri.parse(widget.embedUrl);
        if (emb.hasScheme && emb.host.isNotEmpty) {
          headers['Origin'] = '${emb.scheme}://${emb.host}';
        }
      } catch (_) {}

      http.Response res;
      try {
        res = await http
            .head(uri, headers: headers)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        res = await http.get(uri, headers: {
          ...headers,
          'Range': 'bytes=0-1023',
        }).timeout(const Duration(seconds: 4));
      }

      final code = res.statusCode;
      if (code != 200 && code != 206 && code != 301 && code != 302) {
        if (code >= 500) return false; // transient – allow later retry
        _validatedBad.add(mediaUrl);
        return false;
      }

      final ctype = (res.headers['content-type'] ?? '').toLowerCase();
      if (ctype.contains('text/html') || ctype.contains('application/json')) {
        _validatedBad.add(mediaUrl);
        return false;
      }

      _validatedOk.add(mediaUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetches an HLS master playlist, parses out every rendition with real
  /// RESOLUTION/BANDWIDTH. Returns the list of variants.
  Future<List<StreamVariant>> _probeAndExpandHls(
      StreamVariant candidate) async {
    final mediaUrl = candidate.url;
    if (_validatedBad.contains(mediaUrl)) return const [];

    try {
      final uri = Uri.parse(mediaUrl);
      final headers = <String, String>{
        'User-Agent': _ua,
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
        'Connection': 'keep-alive',
        'Referer': widget.embedUrl,
      };
      try {
        final emb = Uri.parse(widget.embedUrl);
        if (emb.hasScheme && emb.host.isNotEmpty) {
          headers['Origin'] = '${emb.scheme}://${emb.host}';
        }
      } catch (_) {}

      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 5));

      final code = res.statusCode;
      if (code != 200 && code != 206) {
        if (code < 500) _validatedBad.add(mediaUrl);
        return const [];
      }

      final ctype = (res.headers['content-type'] ?? '').toLowerCase();
      if (ctype.contains('text/html') || ctype.contains('application/json')) {
        _validatedBad.add(mediaUrl);
        return const [];
      }

      final body = res.body;
      if (!body.trimLeft().contains('#EXT')) {
        _validatedBad.add(mediaUrl);
        return const [];
      }

      _validatedOk.add(mediaUrl);

      if (!body.contains('#EXT-X-STREAM-INF')) {
        // Single‑quality media playlist – return as is.
        return [candidate];
      }

      final variants = _parseMasterPlaylist(mediaUrl, body);
      if (variants.isEmpty) {
        return [candidate];
      }
      for (final v in variants) {
        _validatedOk.add(v.url);
      }
      return variants;
    } catch (_) {
      return const [];
    }
  }

  /// Parses the real ABR ladder out of an HLS **master** playlist body.
  List<StreamVariant> _parseMasterPlaylist(String manifestUrl, String body) {
    final variants = <StreamVariant>[];
    final base = Uri.parse(manifestUrl);
    final lines = body.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      int? height;
      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      if (resMatch != null) height = int.tryParse(resMatch.group(2)!);

      int? bandwidth;
      final bwMatch = RegExp(r'(?:AVERAGE-)?BANDWIDTH=(\d+)').firstMatch(line);
      if (bwMatch != null) bandwidth = int.tryParse(bwMatch.group(1)!);

      String? uriLine;
      for (int j = i + 1; j < lines.length; j++) {
        final cand = lines[j].trim();
        if (cand.isEmpty || cand.startsWith('#')) continue;
        uriLine = cand;
        break;
      }
      if (uriLine == null) continue;

      String variantUrl = uriLine;
      if (!variantUrl.startsWith('http')) {
        try {
          variantUrl = base.resolve(variantUrl).toString();
        } catch (_) {
          continue;
        }
      }

      variants.add(StreamVariant(
        url: variantUrl,
        height: height ?? _guessHeight(variantUrl),
        bitrate: bandwidth,
        format: 'hls',
      ));
    }

    variants.sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
    return variants;
  }

  Future<void> _tryFinalizeValidated({bool early = false}) async {
    if (_finished || _validating) return;
    _validating = true;
    try {
      if (_candidates.isEmpty) {
        if (!early) _finalize(early: false);
        return;
      }

      final ranked = List<StreamVariant>.from(_candidates)
        ..sort((a, b) => _score(b).compareTo(_score(a)));

      // Parallel probe top candidates.
      final toProbe = ranked.take(6).toList();
      final expandedLists = await Future.wait(
        toProbe.map((c) async {
          if (c.format == 'hls') {
            return _probeAndExpandHls(c);
          }
          final ok = await _probeUrl(c.url);
          return ok ? <StreamVariant>[c] : const <StreamVariant>[];
        }),
      );

      // Flatten + dedupe.
      final good = <StreamVariant>[];
      final seenUrls = <String>{};
      final seenHeights = <int>{};
      for (final list in expandedLists) {
        for (final v in list) {
          if (!seenUrls.add(v.url)) continue;
          if (v.height != null && !seenHeights.add(v.height!)) continue;
          good.add(v);
        }
      }

      if (good.isNotEmpty) {
        good.sort((a, b) => _score(b).compareTo(_score(a)));
        _emitSuccess(good.first, good);
        return;
      }

      if (!early) {
        if (ranked.isNotEmpty) {
          _emitSuccess(ranked.first, ranked);
        } else {
          _finalize(early: false);
        }
      }
    } finally {
      _validating = false;
    }
  }

  void _emitSuccess(StreamVariant best, List<StreamVariant> all) {
    if (_finished) return;
    _finished = true;
    _finalizeTimer?.cancel();
    _earlyCheckTimer?.cancel();
    widget.onLoading?.call(false);
    widget.onDataExtracted(
      ExtractedStreamData(
        bestUrl: best.url,
        allStreams: List.unmodifiable(all),
        isWebM: best.format == 'webm',
      ),
    );
  }

  void _finalize({bool early = false}) {
    if (_finished) return;

    if (_candidates.isEmpty) {
      while (_iframeIndex < _iframeQueue.length) {
        final next = _iframeQueue[_iframeIndex++];
        if (!_visitedPages.contains(next)) {
          _visitedPages.add(next);
          _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(next)));
          return;
        }
      }

      if (_retryCount < 1) {
        _retryCount++;
        _controller?.reload();
        _armFinalizeTimer();
        return;
      }

      _finished = true;
      _earlyCheckTimer?.cancel();
      widget.onLoading?.call(false);
      widget.onError?.call(
        _isTv ? 'No stream found for this episode.' : 'No streams found',
      );
      return;
    }

    unawaited(_tryFinalizeValidated(early: false));
  }

  void _armFinalizeTimer() {
    _finalizeTimer?.cancel();
    final secs = widget.timeoutSeconds.clamp(6, 22);
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
      || u.indexOf('videoplayback') !== -1
      || u.indexOf('manifest') !== -1
      || u.indexOf('playlist') !== -1;
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
      || u.indexOf('vidking') !== -1
      || u.indexOf('vidsrc') !== -1
      || u.indexOf('vidlink') !== -1
      || u.indexOf('superembed') !== -1
      || u.indexOf('autoembed') !== -1
      || u.indexOf('episode') !== -1
      || u.indexOf('series') !== -1
      || u.indexOf('/tv/') !== -1
      || u.indexOf('/movie/');
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

  function scanVideo() {
    try {
      document.querySelectorAll('video, source').forEach(function(v) {
        if (v.src) report(v.src, 'dom');
        if (v.currentSrc) report(v.currentSrc, 'dom');
      });
    } catch (e) {}
  }
  setInterval(scanVideo, 350);
  setTimeout(scanVideo, 150);
  setTimeout(scanVideo, 500);

  function scanPerf() {
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var i = 0; i < entries.length; i++) {
        report(entries[i].name || '', 'perf');
      }
    } catch (e) {}
  }
  setInterval(scanPerf, 500);
  setTimeout(scanPerf, 200);

  function scanIframes() {
    try {
      document.querySelectorAll('iframe').forEach(function(f) {
        if (f.src) report(f.src, 'iframe');
      });
    } catch (e) {}
  }
  setInterval(scanIframes, 450);
  setTimeout(scanIframes, 180);

  function scanHtml() {
    try {
      var html = document.documentElement && document.documentElement.innerHTML;
      if (!html) return;
      var re = /(https?:\/\/[^\s"'<>\\]+?(?:\.m3u8|\.mp4|\.webm|\.mkv)(?:\?[^\s"'<>\\]*)?)/gi;
      var m;
      while ((m = re.exec(html)) !== null) report(m[1], 'html');
    } catch (e) {}
  }
  setTimeout(scanHtml, 600);
  setTimeout(scanHtml, 1400);
  setTimeout(scanHtml, 2600);

  function tryPlay() {
    try {
      document.querySelectorAll('video').forEach(function(v) {
        v.muted = true;
        v.play().catch(function() {});
      });
      var selectors = 'button, [role=button], .play, .play-btn, #play, .vjs-big-play-button, .plyr__control--overlaid, .jw-icon-display';
      var btns = document.querySelectorAll(selectors);
      for (var i = 0; i < btns.length; i++) {
        var t = ((btns[i].innerText || '') + ' ' + (btns[i].className || '') + ' ' + (btns[i].id || '')).toLowerCase();
        if (t.indexOf('play') !== -1 || t.indexOf('start') !== -1) {
          try { btns[i].click(); } catch (e) {}
        }
      }
    } catch (e) {}
  }
  setTimeout(tryPlay, 250);
  setTimeout(tryPlay, 600);
  setTimeout(tryPlay, 1100);
  setTimeout(tryPlay, 2000);

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
        cacheEnabled: true,
        clearCache: false,
        supportZoom: false,
        disableHorizontalScroll: true,
        disableVerticalScroll: true,
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
              if (type == 'log') return null;

              final url =
                  map['url']?.toString() ?? map['responseURL']?.toString();
              if (url == null) return null;

              if (type == 'iframe') {
                _addCandidate({'url': url});
              } else {
                _addCandidate({
                  'url': url,
                  'height': map['height'],
                  'bitrate': map['bitrate'],
                });
              }
            } catch (_) {}
            return null;
          },
        );
      },
      onLoadStop: (controller, url) async {
        try {
          await controller.evaluateJavascript(source: _injectJS());
        } catch (_) {}
        _armFinalizeTimer();

        _earlyCheckTimer?.cancel();
        _earlyCheckTimer = Timer(const Duration(milliseconds: 1400), () {
          if (!_finished && _candidates.isNotEmpty) {
            unawaited(_tryFinalizeValidated(early: true));
          }
        });
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