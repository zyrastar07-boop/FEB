import 'package:http/http.dart' as http;

/// [http.BaseClient] wrapper that explicitly negotiates gzip for API/JSON
/// traffic.
///
/// Dart's `dart:io` HttpClient already sends `Accept-Encoding: gzip` and
/// transparently decompresses gzip responses by default (`autoUncompress`),
/// and the browser fetch on web handles it natively — so this wrapper's job
/// is to make that explicit and consistent for every request it wraps, so
/// payloads from the Cloudflare Worker proxy (which compresses responses
/// with gzip/brotli automatically) arrive as small as possible.
///
/// Rules:
/// - If the caller already set an `Accept-Encoding` header (e.g. media
///   streams in DownloadService deliberately use `identity`), it is left
///   untouched — media download paths are NEVER routed through here.
/// - Brotli is intentionally NOT requested from native clients: `dart:io`
///   has no brotli decoder, so a brotli response would arrive undecodable.
///   Brotli stays a server-side optimization (Cloudflare Workers), which is
///   negotiated automatically between the client and the CDN edge.
class CompressionClient extends http.BaseClient {
  CompressionClient(this._inner);

  final http.Client _inner;

  static const String _gzip = 'gzip';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.headers.containsKey('Accept-Encoding')) {
      request.headers['Accept-Encoding'] = _gzip;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}