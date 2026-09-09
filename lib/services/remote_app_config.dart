import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'compression_client.dart';
import 'http_response_cache.dart';

/// Remote kill-switch + feed / category control.
/// Fetched from Cloudflare Worker `/config` (backed by KV).
class RemoteAppConfig extends ChangeNotifier {
  RemoteAppConfig._();
  static final RemoteAppConfig instance = RemoteAppConfig._();

  bool _loaded = false;
  bool _isAppActive = true;
  String _maintenanceMessage =
      'PhonoFilm is temporarily unavailable. Please try again later.';
  String _minAppVersion = '1.0.0';
  List<int> _featuredMovieIds = const [];
  List<int> _featuredTvIds = const [];
  List<String> _hiddenCategories = const [];
  Map<String, dynamic> _categoryOverrides = const {};
  List<String> _homeSectionsOrder = const [
    'continue_watching',
    'action',
    'scifi',
    'classics',
    'romance',
    'now_playing',
    'award',
    'anime',
    'tv',
    'asian',
  ];
  bool _forceUpdate = false;
  String _forceUpdateUrl = '';

  bool get isLoaded => _loaded;
  bool get isAppActive => _isAppActive;
  String get maintenanceMessage => _maintenanceMessage;
  String get minAppVersion => _minAppVersion;
  List<int> get featuredMovieIds => _featuredMovieIds;
  List<int> get featuredTvIds => _featuredTvIds;
  List<String> get hiddenCategories => _hiddenCategories;
  Map<String, dynamic> get categoryOverrides => _categoryOverrides;
  List<String> get homeSectionsOrder => _homeSectionsOrder;
  bool get forceUpdate => _forceUpdate;
  String get forceUpdateUrl => _forceUpdateUrl;

  bool isCategoryHidden(String categoryType) =>
      _hiddenCategories.contains(categoryType);

  /// Call once at app start (before Home). Safe to call again to refresh.
  ///
  /// Backed by [HttpResponseCache] (5-min stale-while-revalidate) so
  /// repeat launches don't re-hit the Worker.
  Future<void> load({Duration timeout = const Duration(seconds: 8)}) async {
    final url = Uri.parse(ApiConfig.configUrl);

    // Routes through the load-balancing client so 5xx / 429 quaratines
    // the mirror; the SWR cache prevents repeat fetches.
    final client = _BalancingClient();

    dynamic raw;
    try {
      raw = await HttpResponseCache.instance.getJson(url, client: client);
    } catch (e) {
      ApiConfig.reportProxyFailure();
      debugPrint('RemoteAppConfig load failed: $e');
    } finally {
      client.close();
    }

    // HttpResponseCache returns null on cold fetch failure OR parse
    // failure; either way report failure so the load balancer learns.
    if (raw == null) {
      ApiConfig.reportProxyFailure();
    } else {
      ApiConfig.reportProxySuccess();
    }

    final data = raw is Map<String, dynamic> ? raw : null;
    if (data != null) {
      _isAppActive = data['is_app_active'] as bool? ?? true;
      _maintenanceMessage =
          (data['maintenance_message'] as String?) ?? _maintenanceMessage;
      _minAppVersion =
          (data['min_app_version'] as String?) ?? _minAppVersion;
      _featuredMovieIds = _toIntList(data['featured_movie_ids']);
      _featuredTvIds = _toIntList(data['featured_tv_ids']);
      _hiddenCategories = (data['hidden_categories'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      _categoryOverrides =
          (data['category_overrides'] as Map?)?.cast<String, dynamic>() ??
              const {};
      final order = (data['home_sections_order'] as List?)
          ?.map((e) => e.toString())
          .toList();
      if (order != null && order.isNotEmpty) {
        _homeSectionsOrder = order;
      }
      _forceUpdate = data['force_update'] as bool? ?? false;
      _forceUpdateUrl = (data['force_update_url'] as String?) ?? '';
    }
    _loaded = true;
    notifyListeners();
  }

  List<int> _toIntList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e is int ? e : int.tryParse(e.toString()))
        .whereType<int>()
        .toList();
  }
}

/// Tiny loader-balancing client wrapper around CompressionClient so the
/// load balancer in [ApiConfig] still sees success/failure outcomes when
/// we go through [HttpResponseCache].
class _BalancingClient extends http.BaseClient {
  final http.Client _inner = CompressionClient(http.Client());

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
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