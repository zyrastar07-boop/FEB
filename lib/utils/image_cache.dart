import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralized image cache configuration for [CachedNetworkImage] +
/// Flutter's `ImageCache`.
///
/// Goals:
///   * Bound memory so a long scroll session doesn't OOM on low-end
///     devices (Android Go, older iPhones). Default 200 MB / 500 entries
///     is generous; we trim to 100 MB / 300 entries.
///   * Request WebP from servers that support it (TMDB does via
///     `image.tmdb.org/t/p/{format}/{path}.webp`). Older servers ignore
///     the Accept header and still return JPEG/PNG.
///   * Provide a single `webpHeaders` constant so call sites don't drift.
///
/// Call [ImageCacheConfig.apply] from `main()` before `runApp`.
class ImageCacheConfig {
  ImageCacheConfig._();

  static const Map<String, String> webpHeaders = <String, String>{
    'Accept': 'image/webp,image/avif,image/png,image/jpeg,image/*;q=0.8',
  };

  /// Tighten Flutter's [PaintingBinding.imageCache]. Idempotent — safe
  /// to call from main().
  static void apply() {
    // imageCache is a getter on PaintingBinding; on the Flutter engine
    // it's mutable.
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 300;
    cache.maximumSizeBytes = 100 * 1024 * 1024; // 100 MB
    if (kDebugMode) {
      debugPrint(
        '[ImageCacheConfig] applied: '
        'maxSize=${cache.maximumSize}, '
        'maxBytes=${cache.maximumSizeBytes}',
      );
    }
  }

  /// Drop everything in the in-memory image cache. Call on logout or
  /// when memory pressure is reported.
  static void evictAll() {
    PaintingBinding.instance.imageCache.clear();
    CachedNetworkImage.evictFromCache('');
  }
}
