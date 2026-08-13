import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ExtractedStream {
  final String videoUrl;
  final Map<String, String> headers;

  ExtractedStream({required this.videoUrl, required this.headers});
}

class StreamExtractor {
  /// Loads the embed URL off-screen, intercepts network requests,
  /// and captures the direct .m3u8 master playlist link.
  static Future<ExtractedStream?> extractDirectStream(String embedUrl) async {
    final Completer<ExtractedStream?> completer = Completer();
    HeadlessInAppWebView? headlessWebView;

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(embedUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        blockNetworkImage: true, // Speeds up loading
        useShouldInterceptRequest: true,
      ),
      onLoadResource: (controller, resource) {
        final url = resource.url.toString();

        // Detect HLS playlist (.m3u8) or direct MP4 URLs
        if (url.contains('.m3u8') || (url.contains('.mp4') && !url.contains('ad'))) {
          if (!completer.isCompleted) {
            completer.complete(
              ExtractedStream(
                videoUrl: url,
                headers: {
                  'Referer': embedUrl,
                  'User-Agent': "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                },
              ),
            );
            headlessWebView?.dispose();
          }
        }
      },
    );

    await headlessWebView.run();

    // Timeout fallback after 12 seconds if no stream is captured
    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        headlessWebView?.dispose();
        return null;
      },
    );
  }
}