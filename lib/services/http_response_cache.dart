import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Process-wide stale-while-revalidate cache for read-only JSON GETs.
///
/// Why: the Worker proxies the same `/tmdb/configuration`, `/config`, and
/// `/tmdb/...` payloads to every device. Caching them at the CF edge
/// covers cross-device reuse, but per-device we still pay a full
/// round-trip on every cold launch. A 60-second SWR cache on top of the
/// edge cache keeps cold-launch latency at ~0 ms when the user has the
/// app open repeatedly (e.g. daily active usage).
///
/// Constraints:
///   * GETs only — POSTs (Patreon verify, Verify.et, write APIs) are
///     explicitly NOT routed through here.
///   * Pure-URL keyed; query parameters are part of the key.
///   * On parse failure we cache the raw bytes too so the next call
///     gets the same bytes back without re-fetching.
///   * Bounded LRU so a long-running session can't OOM.
///   * Fires the network refresh in the background once the cached
///     value is returned — callers always see something immediately.
///
/// The cache is intentionally separate from the
/// [cached_network_image] disk cache used for posters; that's an
/// image-specific pipeline with different size economics.
class HttpResponseCache {
  HttpResponseCache._();

  static final HttpResponseCache instance = HttpResponseCache._();

  static const Duration _defaultFreshWindow = Duration(minutes: 5);

  /// Max entries before we evict the oldest (insertion order).
  static const int _maxEntries = 64;

  final Map<String, _Entry> _store = <String, _Entry>{};
  final Map<String, Future<_Entry?>> _inflight = <String, Future<_Entry?>>{};

  /// GET [url] via [client]. Returns the response body as a parsed JSON
  /// object (Map / List / primitive). Falls back to `null` on parse
  /// failure so the caller can decide what to do.
  Future<dynamic> getJson(
    Uri url, {
    http.Client? client,
    Duration freshWindow = _defaultFreshWindow,
    Map<String, String>? headers,
  }) async {
    final raw = await getRaw(
      url,
      client: client,
      freshWindow: freshWindow,
      headers: headers,
    );
    if (raw == null) return null;
    try {
      return json.decode(raw.body);
    } catch (_) {
      return null;
    }
  }

  /// GET [url] via [client]. Returns the raw response (status + body +
  /// headers) or `null` on failure.
  Future<CachedHttpResponse?> getRaw(
    Uri url, {
    http.Client? client,
    Duration freshWindow = _defaultFreshWindow,
    Map<String, String>? headers,
  }) async {
    final key = url.toString();
    final now = DateTime.now();

    final existing = _store[key];
    if (existing != null) {
      final age = now.difference(existing.fetchedAt);
      if (age < freshWindow) {
        _touch(key);
        return existing.response;
      }
      // Stale → return immediately AND kick off a background refresh.
      _refreshInBackground(key, client, headers);
      return existing.response;
    }

    // Cold cache → fetch (de-dup concurrent calls for the same URL).
    final pending = _inflight[key];
    if (pending != null) {
      final entry = await pending;
      return entry?.response;
    }

    final completer = Completer<_Entry?>();
    _inflight[key] = completer.future;

    try {
      final fresh = await _fetch(client, url, headers);
      if (fresh != null) {
        _put(key, _Entry(fetchedAt: now, response: fresh));
      }
      completer.complete(fresh != null ? _store[key] : null);
      return fresh;
    } catch (e) {
      debugPrint('[HttpResponseCache] fetch failed for $key: $e');
      completer.complete(null);
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<void> _refreshInBackground(
    String key,
    http.Client? client,
    Map<String, String>? headers,
  ) async {
    final url = Uri.parse(key);
    final fresh = await _fetch(client, url, headers);
    if (fresh != null) {
      _put(key, _Entry(fetchedAt: DateTime.now(), response: fresh));
    }
  }

  Future<CachedHttpResponse?> _fetch(
    http.Client? client,
    Uri url,
    Map<String, String>? headers,
  ) async {
    final c = client ?? http.Client();
    try {
      final allHeaders = <String, String>{
        ...?headers,
        'Accept': 'application/json',
      };
      final res = await c
          .get(url, headers: allHeaders)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return CachedHttpResponse(
          statusCode: res.statusCode,
          body: res.body,
          headers: res.headers,
        );
      }
      return null;
    } catch (_) {
      // Caller's ProxyHttpClient wrapper already mirrors 5xx / 429 into
      // the endpoint pool's quarantine logic — we don't need to repeat
      // it here.
      rethrow;
    } finally {
      if (client == null) c.close();
    }
  }

  void _put(String key, _Entry entry) {
    if (_store.length >= _maxEntries && !_store.containsKey(key)) {
      _store.remove(_store.keys.first);
    }
    _store[key] = entry;
  }

  void _touch(String key) {
    // LinkedHashMap keeps insertion order; re-insert to move to MRU end.
    final v = _store.remove(key);
    if (v != null) _store[key] = v;
  }

  /// Test-only: clear the entire cache.
  @visibleForTesting
  void reset() {
    _store.clear();
    _inflight.clear();
  }
}

class _Entry {
  _Entry({required this.fetchedAt, required this.response});
  final DateTime fetchedAt;
  final CachedHttpResponse response;
}

class CachedHttpResponse {
  CachedHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
  final int statusCode;
  final String body;
  final Map<String, String> headers;
}
