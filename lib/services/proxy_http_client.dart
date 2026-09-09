import 'package:http/http.dart' as http;
import 'api_config.dart';

/// [http.BaseClient] wrapper that feeds every request outcome back to the
/// [ApiConfig] load balancer.
///
/// Wrap the shared `_client` in [TmdbService] / [TmdbDetailsService] and the
/// pool automatically learns which worker mirror is healthy: failures
/// (exceptions, 5xx, 429 rate-limit) quarantine the endpoint for a cooldown,
/// successes keep it in rotation. Call sites stay untouched.
class ProxyHttpClient extends http.BaseClient {
  ProxyHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      // Rate-limit / server errors count as endpoint failures so traffic
      // shifts to a healthy mirror; 4xx client errors are NOT endpoint
      // failures (the request itself was wrong, not the mirror).
      if (response.statusCode >= 500 || response.statusCode == 429) {
        ApiConfig.reportProxyFailure();
      } else {
        ApiConfig.reportProxySuccess();
      }
      return response;
    } catch (_) {
      ApiConfig.reportProxyFailure();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}