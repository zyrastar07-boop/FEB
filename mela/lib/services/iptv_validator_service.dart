import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iptv_channel_model.dart';

/// High-performance background stream health validator.
///
/// - Runs lightweight HEAD / range GET requests off the main isolate.
/// - Concurrent batching (default 18 streams at a time).
/// - Aggressive timeouts (2.8 s) for slow networks.
/// - Local cache (SharedPreferences) with 1-hour TTL.
class IptvValidatorService {
  static const String _cacheKey = 'iptv_health_cache_v1';
  static const Duration _cacheTtl = Duration(hours: 1);
  static const int _batchSize = 18;
  static const Duration _requestTimeout = Duration(milliseconds: 2800);

  /// Validate a list of channels. Returns only the healthy ones
  /// (or the original list with [isHealthy] flags updated when [filter] is false).
  Future<List<IptvChannel>> validateChannels(
    List<IptvChannel> channels, {
    bool filter = true,
    void Function(int checked, int total)? onProgress,
  }) async {
    if (channels.isEmpty) return [];

    final prefs = await SharedPreferences.getInstance();
    final cache = await _loadCache(prefs);
    final now = DateTime.now();

    final toCheck = <IptvChannel>[];
    final alreadyHealthy = <IptvChannel>[];

    for (final ch in channels) {
      final cached = cache[ch.streamUrl];
      if (cached != null &&
          now.difference(cached.timestamp) < _cacheTtl) {
        if (cached.isHealthy) {
          alreadyHealthy.add(ch.copyWith(
            isHealthy: true,
            lastValidated: cached.timestamp,
          ));
        }
        // If cached as dead we simply skip it when filtering
      } else {
        toCheck.add(ch);
      }
    }

    if (toCheck.isEmpty) {
      onProgress?.call(channels.length, channels.length);
      return filter ? alreadyHealthy : channels;
    }

    final results = <IptvChannel>[];
    int checked = alreadyHealthy.length;

    // Process in concurrent batches
    for (var i = 0; i < toCheck.length; i += _batchSize) {
      final batch = toCheck.skip(i).take(_batchSize).toList();
      final batchResults = await _validateBatch(batch);

      for (final r in batchResults) {
        cache[r.channel.streamUrl] = _CacheEntry(
          isHealthy: r.isHealthy,
          timestamp: now,
        );
        if (r.isHealthy) {
          results.add(r.channel.copyWith(
            isHealthy: true,
            lastValidated: now,
          ));
        }
      }

      checked += batch.length;
      onProgress?.call(checked, channels.length);

      // Persist cache every couple of batches so we don't lose progress
      if (i % (_batchSize * 3) == 0) {
        await _saveCache(prefs, cache);
      }
    }

    await _saveCache(prefs, cache);

    final healthy = [...alreadyHealthy, ...results];
    if (filter) return healthy;

    return channels.map((c) {
      final match = healthy.cast<IptvChannel?>().firstWhere(
            (h) => h?.id == c.id,
            orElse: () => null,
          );
      return match ?? c.copyWith(isHealthy: false);
    }).toList();
  }

  Future<List<_ValidationResult>> _validateBatch(
    List<IptvChannel> batch,
  ) async {
    // Use compute / isolate for the network work so the UI stays buttery
    return compute(_validateBatchIsolate, batch.map((c) => c.streamUrl).toList())
        .then((raw) {
      final results = <_ValidationResult>[];
      for (var i = 0; i < batch.length; i++) {
        results.add(_ValidationResult(
          channel: batch[i],
          isHealthy: raw[i],
        ));
      }
      return results;
    });
  }

  /// Isolate entry point – pure Dart, no Flutter dependencies.
  static Future<List<bool>> _validateBatchIsolate(List<String> urls) async {
    final client = HttpClient()
      ..connectionTimeout = _requestTimeout
      ..idleTimeout = _requestTimeout;

    final futures = urls.map((url) => _checkSingle(client, url));
    final results = await Future.wait(futures);
    client.close(force: true);
    return results;
  }

  static Future<bool> _checkSingle(HttpClient client, String url) async {
    try {
      final uri = Uri.parse(url);
      final request = await client.openUrl('GET', uri).timeout(_requestTimeout);

      // Ask only for the first kilobyte – enough to know the stream is alive
      request.headers
        ..set(HttpHeaders.rangeHeader, 'bytes=0-1023')
        ..set(HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 IPTV-Validator/1.0')
        ..set(HttpHeaders.acceptHeader, '*/*');

      final response = await request.close().timeout(_requestTimeout);

      // Accept 200 and 206 (partial content)
      final ok = response.statusCode == 200 || response.statusCode == 206;

      // Drain the body quickly so the connection can be reused / closed
      await response.drain().timeout(const Duration(milliseconds: 800));

      return ok;
    } catch (_) {
      return false;
    }
  }

  // ── Cache helpers ────────────────────────────────────────────────────────

  Future<Map<String, _CacheEntry>> _loadCache(SharedPreferences prefs) async {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) {
        final m = v as Map<String, dynamic>;
        return MapEntry(
          k,
          _CacheEntry(
            isHealthy: m['h'] as bool,
            timestamp: DateTime.parse(m['t'] as String),
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(
    SharedPreferences prefs,
    Map<String, _CacheEntry> cache,
  ) async {
    // Keep cache size reasonable
    if (cache.length > 4000) {
      final sorted = cache.entries.toList()
        ..sort((a, b) => b.value.timestamp.compareTo(a.value.timestamp));
      cache
        ..clear()
        ..addEntries(sorted.take(3000));
    }

    final encoded = jsonEncode(
      cache.map((k, v) => MapEntry(k, {
            'h': v.isHealthy,
            't': v.timestamp.toIso8601String(),
          })),
    );
    await prefs.setString(_cacheKey, encoded);
  }

  /// Force-clear the health cache (useful after a major playlist update).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}

class _CacheEntry {
  final bool isHealthy;
  final DateTime timestamp;
  _CacheEntry({required this.isHealthy, required this.timestamp});
}

class _ValidationResult {
  final IptvChannel channel;
  final bool isHealthy;
  _ValidationResult({required this.channel, required this.isHealthy});
}