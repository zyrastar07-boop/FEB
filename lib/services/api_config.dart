import 'endpoint_pool.dart';

/// Central endpoint configuration for the Cloudflare Worker proxy.
///
/// Traffic is routed through an [EndpointPool] load balancer so the app keeps
/// working if the primary worker is down or rate-limited:
///
/// - The primary worker URL below is always used first.
/// - Additional mirrors can be injected at build time without code changes:
///
///   ```bash
///   flutter build apk --dart-define=PROXY_MIRRORS=https://mirror-a.workers.dev,https://mirror-b.workers.dev
///   ```
///
///   Mirrors are rotated round-robin and quarantined briefly after repeated
///   failures, then automatically re-enabled.
class ApiConfig {
  /// Primary worker (always first in the pool).
  ///
  /// Defaults to the production phonofilm-proxy worker. Override at build
  /// time with `--dart-define=PROXY_PRIMARY_URL=https://your-worker.dev`
  /// (see `.env.example`). Useful for forks, staging builds, and CI.
  static const String _primaryBaseUrl = String.fromEnvironment(
    'PROXY_PRIMARY_URL',
    defaultValue: 'https://phonofilm-proxy.mela-media-2026.workers.dev',
  );

  /// Optional comma-separated mirror list injected at build time.
  static const String _mirrorsEnv = String.fromEnvironment('PROXY_MIRRORS');

  /// Load-balancing pool: primary first, mirrors after.
  static final EndpointPool _pool = EndpointPool(
    endpoints: _resolveEndpoints(),
  );

  static List<String> _resolveEndpoints() {
    final mirrors = _mirrorsEnv
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return [if (_primaryBaseUrl.isNotEmpty) _primaryBaseUrl, ...mirrors];
  }

  /// Removes any trailing slash to prevent double-slash bugs (//) in endpoints.
  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// Current base URL selected by the load balancer (round-robin).
  static String get proxyBaseUrl => _trimSlash(_pool.next());

  /// Report the last issued proxy call as successful — resets any failure
  /// streak for that endpoint.
  static void reportProxySuccess() => _pool.reportSuccess();

  /// Report the last issued proxy call as failed — quarantines the endpoint
  /// after repeated failures so traffic shifts to healthy mirrors.
  static void reportProxyFailure() => _pool.reportFailure();

  /// Number of currently healthy endpoints (diagnostics).
  static int get healthyEndpointCount => _pool.healthyCount;

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