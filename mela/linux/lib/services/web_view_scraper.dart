import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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

class ExtractedStreamData {
  final String bestUrl;
  final List<StreamVariant> allStreams;

  ExtractedStreamData({
    required this.bestUrl,
    required this.allStreams,
  });
}

class WebViewScraper extends StatefulWidget {
  final String embedUrl;
  final ValueChanged<ExtractedStreamData> onDataExtracted;
  final ValueChanged<String>? onError;

  const WebViewScraper({
    super.key,
    required this.embedUrl,
    required this.onDataExtracted,
    this.onError,
  });

  @override
  State<WebViewScraper> createState() => _WebViewScraperState();
}

class _WebViewScraperState extends State<WebViewScraper> {
  final List<StreamVariant> _candidates = [];
  bool _finished = false;

  Timer? _finalizeTimer;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Safari/537.36';

  void _addCandidate(Map data) {
    final url = data['url'];
    if (url == null) return;

    final format = _detectFormat(url);

    _candidates.add(
      StreamVariant(
        url: url,
        height: data['height'],
        bitrate: data['bitrate'],
        format: format,
      ),
    );
  }

  String _detectFormat(String url) {
    if (url.contains('.m3u8')) return 'hls';
    if (url.contains('.mp4')) return 'mp4';
    if (url.contains('.webm')) return 'webm';
    return 'unknown';
  }

  StreamVariant _rankBest() {
    _candidates.sort((a, b) {
      int scoreA = _score(a);
      int scoreB = _score(b);
      return scoreB.compareTo(scoreA);
    });

    return _candidates.first;
  }

  int _score(StreamVariant s) {
    int score = 0;

    // format priority
    if (s.format == 'hls') score += 1000;
    if (s.format == 'mp4') score += 600;
    if (s.format == 'webm') score += 400;

    // resolution
    if (s.height != null) score += s.height! * 5;

    // bitrate
    if (s.bitrate != null) score += (s.bitrate! ~/ 1000);

    return score;
  }

  void _finalize() {
    if (_finished || _candidates.isEmpty) {
      widget.onError?.call('No streams found');
      return;
    }

    _finished = true;

    final best = _rankBest();

    widget.onDataExtracted(
      ExtractedStreamData(
        bestUrl: best.url,
        allStreams: _candidates,
      ),
    );
  }

  String _injectJS() {
    return '''
(function() {

  function send(obj){
    window.flutter_inappwebview.callHandler(
      'stream',
      JSON.stringify(obj)
    );
  }

  function report(url){
    if(!url) return;

    if(/\\.(m3u8|mp4|webm)/i.test(url)){
      send({url:url});
    }
  }

  // ======================
  // VIDEO TAGS
  // ======================
  setInterval(()=>{
    document.querySelectorAll('video, source').forEach(v=>{
      if(v.src) report(v.src);
    });
  },1500);

  // ======================
  // XHR
  // ======================
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(){
    this.addEventListener('load', ()=>{
      report(this.responseURL);
    });
    open.apply(this, arguments);
  };

  // ======================
  // FETCH
  // ======================
  const oldFetch = window.fetch;
  window.fetch = function(){
    return oldFetch.apply(this, arguments).then(res=>{
      report(res.url);
      return res;
    });
  };

  // ======================
  // PERFORMANCE API
  // ======================
  setInterval(()=>{
    performance.getEntries().forEach(e=>{
      report(e.name);
    });
  },2000);

  // ======================
  // IFRAME DETECTION 🔥
  // ======================
  setInterval(()=>{
    document.querySelectorAll('iframe').forEach(f=>{
      try{
        if(f.src) report(f.src);
      }catch(e){}
    });
  },2000);

})();
true;
''';
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.embedUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        userAgent: _ua,
      ),

      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'stream',
          callback: (args) {
            if (args.isEmpty) return;

            try {
              final data = jsonDecode(args[0]);
              _addCandidate(data);
            } catch (_) {}
          },
        );
      },

      onLoadStop: (controller, _) async {
        await controller.evaluateJavascript(source: _injectJS());

        // 🔥 allow time to collect multiple streams
        _finalizeTimer?.cancel();
        _finalizeTimer = Timer(const Duration(seconds: 12), _finalize);
      },
    );
  }
}