/// Central endpoint for the Cloudflare Worker proxy.
/// Replace with your deployed worker URL after `wrangler deploy`.
class ApiConfig {
  /// Example: https://phonofilm-proxy.YOUR_SUBDOMAIN.workers.dev
  static const String _rawBaseUrl =
      'https://phonofilm-proxy.mela-media-2026.workers.dev';

  /// Removes any trailing slash to prevent double-slash bugs (//) in endpoints.
  static String get proxyBaseUrl =>
      _rawBaseUrl.endsWith('/') ? _rawBaseUrl.substring(0, _rawBaseUrl.length - 1) : _rawBaseUrl;

  static String tmdb(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return '$proxyBaseUrl/tmdb$p';
  }

  static String get configUrl => '$proxyBaseUrl/config';

  static String wyzieSearch(Map<String, String> params) {
    final q = Uri(queryParameters: params).query;
    return '$proxyBaseUrl/wyzie/search?$q';
  }

  static String wyzieFetch(String subtitleFileUrl) {
    return '$proxyBaseUrl/wyzie/fetch?url=${Uri.encodeComponent(subtitleFileUrl)}';
  }
}