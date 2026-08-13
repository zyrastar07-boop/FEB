import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import 'download_notifier.dart';

enum DownloadStatus { queued, resolving, downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String title;
  final String posterUrl;
  final String videoUrl;
  final String quality;
  final String codec;
  final String sizeLabel;
  final String mediaType; // movie | tv
  final int season;
  final int episode;

  double progress; // 0.0 – 1.0
  DownloadStatus status;
  String? localPath;
  String? error;
  int bytesReceived;
  int totalBytes;

  /// Live metrics (updated during download).
  double speedBps; // bytes per second
  int? etaSeconds; // remaining seconds, null if unknown

  StreamSubscription? subscription;
  http.Client? client;
  bool cancelRequested;
  final String? referer;

  /// Keep-alive timer for the active host.
  Timer? keepAliveTimer;

  /// Rolling window for speed calculation.
  final List<_SpeedSample> _speedSamples = [];
  DateTime? lastProgressAt;

  DownloadItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.videoUrl,
    required this.quality,
    required this.codec,
    required this.sizeLabel,
    this.mediaType = 'movie',
    this.season = 1,
    this.episode = 1,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.localPath,
    this.error,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.speedBps = 0,
    this.etaSeconds,
    this.cancelRequested = false,
    this.referer,
  });

  String get displayLabel {
    if (mediaType == 'tv') {
      return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} · $quality';
    }
    return quality;
  }

  /// Human-readable speed, e.g. "2.4 MB/s" or "480 KB/s".
  String get speedLabel {
    if (speedBps <= 0) return '—';
    if (speedBps >= 1024 * 1024) {
      return '${(speedBps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (speedBps >= 1024) {
      return '${(speedBps / 1024).toStringAsFixed(0)} KB/s';
    }
    return '${speedBps.toStringAsFixed(0)} B/s';
  }

  /// Human-readable ETA, e.g. "3 mins left" or "45s left".
  String get etaLabel {
    final s = etaSeconds;
    if (s == null || s <= 0) return '';
    if (s < 60) return '${s}s left';
    if (s < 3600) {
      final m = (s / 60).ceil();
      return '$m min${m == 1 ? '' : 's'} left';
    }
    final h = s ~/ 3600;
    final m = ((s % 3600) / 60).round();
    return '${h}h ${m}m left';
  }

  /// Formatted "received / total" or just received when total unknown.
  String get sizeProgressLabel {
    final recv = formatBytes(bytesReceived);
    if (totalBytes > 0) {
      return '$recv / ${formatBytes(totalBytes)}';
    }
    if (bytesReceived > 0) return recv;
    return sizeLabel.isNotEmpty ? sizeLabel : '—';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final digits = value >= 100 || i == 0 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[i]}';
  }

  void recordProgress(int newBytesReceived) {
    final now = DateTime.now();
    final prev = bytesReceived;
    bytesReceived = newBytesReceived;

    if (lastProgressAt != null && newBytesReceived > prev) {
      final deltaBytes = newBytesReceived - prev;
      final deltaMs = now.difference(lastProgressAt!).inMilliseconds;
      if (deltaMs > 0) {
        _speedSamples.add(_SpeedSample(now, deltaBytes, deltaMs));
        // Keep ~4 seconds of samples
        _speedSamples.removeWhere(
          (s) => now.difference(s.at).inSeconds > 4,
        );
        if (_speedSamples.isNotEmpty) {
          final totalB =
              _speedSamples.fold<int>(0, (a, s) => a + s.bytes);
          final totalMs =
              _speedSamples.fold<int>(0, (a, s) => a + s.ms);
          if (totalMs > 0) {
            speedBps = totalB * 1000.0 / totalMs;
          }
        }
      }
    }
    lastProgressAt = now;

    if (totalBytes > 0) {
      progress = (bytesReceived / totalBytes).clamp(0.0, 1.0);
      if (speedBps > 0 && bytesReceived < totalBytes) {
        etaSeconds = ((totalBytes - bytesReceived) / speedBps).ceil();
      } else {
        etaSeconds = null;
      }
    } else if (progress < 0.99) {
      // HLS without known total: leave progress as set by caller
      etaSeconds = null;
    }
  }

  void resetMetrics() {
    speedBps = 0;
    etaSeconds = null;
    _speedSamples.clear();
    lastProgressAt = null;
  }
}

class _SpeedSample {
  final DateTime at;
  final int bytes;
  final int ms;
  _SpeedSample(this.at, this.bytes, this.ms);
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal();

  final List<DownloadItem> _items = [];
  List<DownloadItem> get items => List.unmodifiable(_items);

  DownloadItem? getById(String id) {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  bool isDownloadedLocally(String id) {
    final item = getById(id);
    if (item == null || item.status != DownloadStatus.completed) return false;
    if (item.localPath == null) return false;
    return File(item.localPath!).existsSync();
  }

  File? getLocalFile(String id) {
    if (!isDownloadedLocally(id)) return null;
    return File(getById(id)!.localPath!);
  }

  /// Enqueue download for a movie or TV episode.
  Future<void> enqueueDownload({
    required Movie movie,
    required String videoUrl,
    required String quality,
    required String codec,
    required String sizeLabel,
    String mediaType = 'movie',
    int season = 1,
    int episode = 1,
    String? referer,
  }) async {
    final id = mediaType == 'tv'
        ? '${movie.id}_s${season}_e${episode}_$quality'
        : '${movie.id}_$quality';

    if (_items.any((i) =>
        i.id == id &&
        (i.status == DownloadStatus.downloading ||
            i.status == DownloadStatus.resolving))) {
      return;
    }

    _items.removeWhere((i) => i.id == id);

    final item = DownloadItem(
      id: id,
      title: mediaType == 'tv'
          ? '${movie.title} S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
          : movie.title,
      posterUrl: _posterUrl(movie),
      videoUrl: videoUrl,
      quality: quality,
      codec: codec,
      sizeLabel: sizeLabel,
      mediaType: mediaType,
      season: season,
      episode: episode,
      status: DownloadStatus.queued,
      referer: referer,
    );

    _items.insert(0, item);
    notifyListeners();
    unawaited(_runJob(item));
  }

  String _posterUrl(Movie movie) {
    try {
      final dynamic m = movie;
      if (m.posterUrl is String && (m.posterUrl as String).isNotEmpty) {
        return m.posterUrl as String;
      }
      final path = m.posterPath;
      if (path is String && path.isNotEmpty) {
        if (path.startsWith('http')) return path;
        return 'https://image.tmdb.org/t/p/w500$path';
      }
    } catch (_) {}
    return '';
  }

  Future<void> _runJob(DownloadItem item) async {
    try {
      final url = item.videoUrl.trim();

      if (url.isEmpty) {
        item.status = DownloadStatus.failed;
        item.error = 'No stream URL provided';
        notifyListeners();
        return;
      }

      if (_isEmbedPage(url)) {
        item.status = DownloadStatus.failed;
        item.error =
            'Player page URL cannot be downloaded. Need a direct .mp4 or .m3u8 stream link.';
        notifyListeners();
        return;
      }

      item.status = DownloadStatus.downloading;
      item.resetMetrics();
      notifyListeners();

      _startKeepAlive(item, url);

      final dir = await _downloadDir();
      final safeName = item.id.replaceAll(RegExp(r'[^\w\-.]'), '_');

      final lowerUrl = url.toLowerCase();
      if (lowerUrl.contains('.m3u8') ||
          lowerUrl.contains('/hls/') ||
          lowerUrl.contains('manifest')) {
        await _downloadHls(item, url, '${dir.path}/$safeName.ts');
      } else {
        await _downloadProgressive(item, url, '${dir.path}/$safeName.mp4');
      }
    } catch (e) {
      if (item.cancelRequested) return;
      _stopKeepAlive(item);
      item.status = DownloadStatus.failed;
      item.error = e.toString();
      item.resetMetrics();
      notifyListeners();
    }
  }

  void _startKeepAlive(DownloadItem item, String mediaUrl) {
    _stopKeepAlive(item);
    String? host;
    try {
      host = Uri.parse(mediaUrl).host;
    } catch (_) {}
    if (host == null || host.isEmpty) return;

    item.keepAliveTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (item.status != DownloadStatus.downloading || item.cancelRequested) {
        _stopKeepAlive(item);
        return;
      }
      try {
        final client = http.Client();
        try {
          final uri = Uri.parse(mediaUrl);
          final origin = '${uri.scheme}://${uri.host}';
          await client
              .head(
                Uri.parse(origin),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Connection': 'keep-alive',
                  if (item.referer != null && item.referer!.isNotEmpty)
                    'Referer': item.referer!,
                },
              )
              .timeout(const Duration(seconds: 4));
        } finally {
          client.close();
        }
      } catch (_) {}
    });
  }

  void _stopKeepAlive(DownloadItem item) {
    item.keepAliveTimer?.cancel();
    item.keepAliveTimer = null;
  }

  bool _isEmbedPage(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.webm') ||
        lower.contains('.ts') ||
        lower.contains('/hls/') ||
        lower.contains('googlevideo') ||
        lower.contains('videoplayback')) {
      return false;
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return true;
    return (lower.contains('vidfast') ||
            lower.contains('videasy') ||
            lower.contains('cinesrc') ||
            lower.contains('cineplay') ||
            lower.contains('/embed')) &&
        !lower.contains('.m3u8') &&
        !lower.contains('.mp4');
  }

  Map<String, String> _mediaHeaders(String mediaUrl, String? referer) {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Connection': 'keep-alive',
    };
    try {
      final uri = Uri.parse(mediaUrl);
      headers['Origin'] = '${uri.scheme}://${uri.host}';
    } catch (_) {}
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
      try {
        final r = Uri.parse(referer);
        headers['Origin'] = '${r.scheme}://${r.host}';
      } catch (_) {}
    }
    return headers;
  }

  Future<Directory> _downloadDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _downloadProgressive(
    DownloadItem item,
    String url,
    String outPath,
  ) async {
    final file = File(outPath);
    item.client = http.Client();

    final headers = _mediaHeaders(url, item.referer);
    int existing = 0;
    if (await file.exists()) {
      existing = await file.length();
      if (existing > 0) headers['Range'] = 'bytes=$existing-';
    }

    http.StreamedResponse? response;
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (item.cancelRequested) return;
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(headers);
        response = await item.client!.send(request).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode == 200 || response.statusCode == 206) {
          lastError = null;
          break;
        }
        lastError = Exception('HTTP ${response.statusCode}');
        response = null;
      } catch (e) {
        lastError = e;
        response = null;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }

    if (response == null) {
      throw lastError ?? Exception('Failed to start download');
    }

    final contentLength = response.contentLength ?? 0;
    if (response.statusCode == 206) {
      item.totalBytes = existing + contentLength;
      item.bytesReceived = existing;
    } else {
      item.totalBytes = contentLength;
      item.bytesReceived = 0;
    }

    final sink = file.openWrite(mode: existing > 0 && response.statusCode == 206 ? FileMode.append : FileMode.write);
    var lastNotify = DateTime.now();

    try {
      await for (final chunk in response.stream) {
        if (item.cancelRequested) break;
        sink.add(chunk);
        item.recordProgress(item.bytesReceived + chunk.length);

        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds > 250) {
          lastNotify = now;
          notifyListeners();
          DownloadNotifier.showProgress(
            jobId: item.id,
            title: item.title,
            qualityLabel: item.quality,
            progress: (item.progress * 100).toInt(),
            isActive: true,
            bodyText: '${item.sizeProgressLabel} · ${item.speedLabel}',
          );
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (item.cancelRequested) return;

    _stopKeepAlive(item);
    item.status = DownloadStatus.completed;
    item.progress = 1.0;
    item.localPath = outPath;
    item.resetMetrics();
    notifyListeners();
    DownloadNotifier.showCompleted(
      jobId: item.id,
      title: item.title,
      qualityLabel: item.quality,
    );
  }

  Future<void> _downloadHls(
    DownloadItem item,
    String playlistUrl,
    String outPath,
  ) async {
    final client = http.Client();
    item.client = client;
    try {
      final headers = _mediaHeaders(playlistUrl, item.referer);
      final masterRes = await client.get(Uri.parse(playlistUrl), headers: headers);
      if (masterRes.statusCode != 200) {
        throw Exception('Failed to fetch M3U8 playlist (${masterRes.statusCode})');
      }

      String targetPlaylist = playlistUrl;
      var body = masterRes.body;
      if (body.contains('#EXT-X-STREAM-INF')) {
        targetPlaylist = _selectBestHlsVariant(playlistUrl, body);
        final subRes = await client.get(Uri.parse(targetPlaylist), headers: headers);
        if (subRes.statusCode != 200) {
          throw Exception('Failed to fetch variant playlist');
        }
        body = subRes.body;
      }

      final segmentUrls = _parseSegmentUrls(targetPlaylist, body);
      if (segmentUrls.isEmpty) {
        throw Exception('No video segments found in playlist');
      }

      item.totalBytes = 0;
      item.bytesReceived = 0;
      final file = File(outPath);
      final sink = file.openWrite(mode: FileMode.write);

      var downloadedSegs = 0;
      var lastNotify = DateTime.now();

      try {
        for (var i = 0; i < segmentUrls.length; i++) {
          if (item.cancelRequested) break;
          final segUrl = segmentUrls[i];
          final segHeaders = _mediaHeaders(segUrl, item.referer);

          List<int>? bytes;
          for (var attempt = 0; attempt < 3; attempt++) {
            if (item.cancelRequested) break;
            try {
              final res = await client.get(Uri.parse(segUrl), headers: segHeaders).timeout(const Duration(seconds: 15));
              if (res.statusCode == 200) {
                bytes = res.bodyBytes;
                break;
              }
            } catch (_) {
              await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
            }
          }

          if (bytes == null) continue;

          sink.add(bytes);
          downloadedSegs++;
          item.recordProgress(item.bytesReceived + bytes.length);
          item.progress = (downloadedSegs / segmentUrls.length).clamp(0.0, 1.0);

          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 300) {
            lastNotify = now;
            notifyListeners();
            DownloadNotifier.showProgress(
              jobId: item.id,
              title: item.title,
              qualityLabel: item.quality,
              progress: (item.progress * 100).toInt(),
              isActive: true,
              bodyText: '${item.sizeProgressLabel} · ${item.speedLabel}',
            );
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (item.cancelRequested) return;

      _stopKeepAlive(item);
      item.status = DownloadStatus.completed;
      item.progress = 1.0;
      item.localPath = outPath;
      item.resetMetrics();
      notifyListeners();
      DownloadNotifier.showCompleted(
        jobId: item.id,
        title: item.title,
        qualityLabel: item.quality,
      );
    } finally {
      client.close();
    }
  }

  String _selectBestHlsVariant(String masterUrl, String masterBody) {
    final lines = masterBody.split('\n');
    const targetH = 1080;
    int bestScore = 1 << 30;
    String? bestUrl;
    int bestBw = -1;
    String? highestUrl;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '') ?? 0;
      final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final h = int.tryParse(resMatch?.group(2) ?? '') ?? 0;
      if (i + 1 >= lines.length) continue;
      var next = lines[i + 1].trim();
      if (next.isEmpty || next.startsWith('#')) continue;
      if (!next.startsWith('http')) {
        next = Uri.parse(masterUrl).resolve(next).toString();
      }
      if (bw >= bestBw) {
        bestBw = bw;
        highestUrl = next;
      }
      if (h > 0) {
        final score = (h - targetH).abs();
        if (score < bestScore) {
          bestScore = score;
          bestUrl = next;
        }
      }
    }
    return bestUrl ?? highestUrl ?? masterUrl;
  }

  List<String> _parseSegmentUrls(String playlistUrl, String body) {
    final base = Uri.parse(playlistUrl);
    final urls = <String>[];
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      urls.add(line.startsWith('http') ? line : base.resolve(line).toString());
    }
    return urls;
  }

  void pauseDownload(String id) {
    final item = getById(id);
    if (item == null || item.status != DownloadStatus.downloading) return;
    item.status = DownloadStatus.paused;
    item.subscription?.pause();
    item.speedBps = 0;
    item.etaSeconds = null;
    _stopKeepAlive(item);
    notifyListeners();
    DownloadNotifier.showProgress(
      jobId: item.id,
      title: item.title,
      qualityLabel: item.quality,
      progress: (item.progress * 100).toInt(),
      isActive: false,
      bodyText: 'Paused',
    );
  }

  void resumeDownload(String id) {
    final item = getById(id);
    if (item == null || item.status != DownloadStatus.paused) return;
    item.status = DownloadStatus.downloading;
    item.resetMetrics();
    notifyListeners();
    if (item.subscription == null || item.client == null) {
      unawaited(_runJob(item));
    } else {
      _startKeepAlive(item, item.videoUrl);
      item.subscription?.resume();
    }
  }

  void retryDownload(String id) {
    final item = getById(id);
    if (item == null) return;
    if (item.status != DownloadStatus.failed &&
        item.status != DownloadStatus.paused) {
      return;
    }
    item.cancelRequested = false;
    item.error = null;
    item.status = DownloadStatus.queued;
    item.resetMetrics();
    notifyListeners();
    unawaited(_runJob(item));
  }

  void cancelDownload(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final item = _items[index];
    item.cancelRequested = true;
    item.subscription?.cancel();
    item.client?.close();
    _stopKeepAlive(item);
    DownloadNotifier.cancel(item.id);
    if (item.localPath != null) {
      try {
        final f = File(item.localPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _items.removeAt(index);
    notifyListeners();
  }

  void clearAll() {
    for (final item in List.of(_items)) {
      cancelDownload(item.id);
    }
  }
}