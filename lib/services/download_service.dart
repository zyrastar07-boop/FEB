import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointycastle/export.dart';
import '../models/movie.dart';
import 'download_notifier.dart';
import 'wyzie_subtitle_service.dart';

enum DownloadStatus {
  queued,
  resolving,
  downloading,
  fusing,
  paused,
  completed,
  failed
}

class DownloadItem {
  final String id;
  final String title;
  final String posterUrl;
  final String videoUrl;
  final String quality;
  final String codec;
  final String sizeLabel;
  final String mediaType;
  final int season;
  final int episode;
  final String? subtitleUrl;
  final bool fuseSubtitles;

  double progress;
  DownloadStatus status;
  String? localPath;
  String? localSubtitlePath;
  String? error;
  int bytesReceived;
  int totalBytes;
  double speedBps;
  int? etaSeconds;
  bool pauseRequested;
  http.Client? client;
  bool cancelRequested;
  final String? referer;
  Timer? keepAliveTimer;
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
    this.subtitleUrl,
    this.fuseSubtitles = true,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.localPath,
    this.localSubtitlePath,
    this.error,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.speedBps = 0,
    this.etaSeconds,
    this.cancelRequested = false,
    this.pauseRequested = false,
    this.referer,
  });

  String get displayLabel {
    if (mediaType == 'tv') {
      return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} · $quality';
    }
    return quality;
  }

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'videoUrl': videoUrl,
        'quality': quality,
        'codec': codec,
        'sizeLabel': sizeLabel,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
        'subtitleUrl': subtitleUrl,
        'fuseSubtitles': fuseSubtitles,
        'progress': progress,
        'status': status.name,
        'localPath': localPath,
        'localSubtitlePath': localSubtitlePath,
        'error': error,
        'bytesReceived': bytesReceived,
        'totalBytes': totalBytes,
        'referer': referer,
      };

  static DownloadItem fromJson(Map<String, dynamic> j) {
    DownloadStatus status;
    try {
      status = DownloadStatus.values.byName(j['status'] as String? ?? 'queued');
    } catch (_) {
      status = DownloadStatus.queued;
    }

    String? resolvedError = j['error']?.toString();

    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.resolving ||
        status == DownloadStatus.fusing) {
      status = DownloadStatus.paused;
      resolvedError ??= 'Interrupted — tap Resume to continue';
    }

    return DownloadItem(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      posterUrl: (j['posterUrl'] ?? '').toString(),
      videoUrl: (j['videoUrl'] ?? '').toString(),
      quality: (j['quality'] ?? '').toString(),
      codec: (j['codec'] ?? '').toString(),
      sizeLabel: (j['sizeLabel'] ?? '').toString(),
      mediaType: (j['mediaType'] ?? 'movie').toString(),
      season: (j['season'] as num?)?.toInt() ?? 1,
      episode: (j['episode'] as num?)?.toInt() ?? 1,
      subtitleUrl: j['subtitleUrl']?.toString(),
      fuseSubtitles: j['fuseSubtitles'] as bool? ?? true,
      progress: (j['progress'] as num?)?.toDouble() ?? 0,
      status: status,
      localPath: j['localPath']?.toString(),
      localSubtitlePath: j['localSubtitlePath']?.toString(),
      error: resolvedError,
      bytesReceived: (j['bytesReceived'] as num?)?.toInt() ?? 0,
      totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      referer: j['referer']?.toString(),
    );
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
        _speedSamples.removeWhere((s) => now.difference(s.at).inSeconds > 4);
        if (_speedSamples.isNotEmpty) {
          final totalB = _speedSamples.fold<int>(0, (a, s) => a + s.bytes);
          final totalMs = _speedSamples.fold<int>(0, (a, s) => a + s.ms);
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

class _AsyncSemaphore {
  _AsyncSemaphore(this._permits);
  int _permits;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final c = _waiters.removeAt(0);
      c.complete();
    } else {
      _permits++;
    }
  }
}

class _HlsPlaylistResponse {
  final String url;
  final String body;
  const _HlsPlaylistResponse(this.url, this.body);
}

class _HlsSegment {
  final String url;
  final String? keyUri;
  final Uint8List? iv;
  const _HlsSegment({required this.url, this.keyUri, this.iv});
}

class _ParsedHlsPlaylist {
  final List<_HlsSegment> segments;
  final String? keyUri;
  final Uint8List? keyIv;
  final int mediaSequence;
  const _ParsedHlsPlaylist({
    required this.segments,
    this.keyUri,
    this.keyIv,
    this.mediaSequence = 0,
  });
}

class _SegResult {
  final int index;
  final List<int>? bytes;
  final String? error;
  const _SegResult({required this.index, this.bytes, this.error});
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal();

  final List<DownloadItem> _items = [];
  List<DownloadItem> get items => List.unmodifiable(_items);

  bool _loaded = false;
  Future<void>? _loadFuture;

  static const int maxConcurrentDownloads = 6;
  static const int hlsSegmentConcurrency = 12;
  static final _AsyncSemaphore _globalSegmentSemaphore = _AsyncSemaphore(24);

  int _activeJobs = 0;

  Future<void> ensureLoaded() {
    _loadFuture ??= _loadFromDisk();
    return _loadFuture!;
  }

  Future<File> _indexFile() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}/downloads_index.json');
  }

  Future<void> _loadFromDisk() async {
    if (_loaded) return;
    try {
      final file = await _indexFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw);
        if (list is List) {
          _items
            ..clear()
            ..addAll(
              list
                  .whereType<Map>()
                  .map((e) => DownloadItem.fromJson(Map<String, dynamic>.from(e))),
            );
          _items.removeWhere((i) {
            if (i.status != DownloadStatus.completed) return false;
            final p = i.localPath;
            if (p == null || p.isEmpty) return true;
            return !File(p).existsSync();
          });
        }
      }
    } catch (e) {
      debugPrint('DownloadService load error: $e');
    }
    _loaded = true;
    notifyListeners();
    _pumpQueue();
  }

  Future<void> _persist() async {
    try {
      await ensureLoaded();
      final file = await _indexFile();
      final data = _items.map((i) => i.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('DownloadService persist error: $e');
    }
  }

  Future<void> flushToDisk() => _persist();

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
    String? subtitleUrl,
    bool fuseSubtitles = true,
  }) async {
    final id = mediaType == 'tv'
        ? '${movie.id}_s${season}_e${episode}_$quality'
        : '${movie.id}_$quality';

    if (_items.any((i) =>
        i.id == id &&
        (i.status == DownloadStatus.downloading ||
            i.status == DownloadStatus.resolving ||
            i.status == DownloadStatus.fusing))) {
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
      subtitleUrl: subtitleUrl,
      fuseSubtitles: fuseSubtitles,
      status: DownloadStatus.queued,
      referer: referer,
    );

    _items.insert(0, item);
    notifyListeners();
    unawaited(_persist());
    _pumpQueue();
  }

  void _pumpQueue() {
    while (_activeJobs < maxConcurrentDownloads) {
      DownloadItem? next;
      for (final i in _items) {
        if (i.status == DownloadStatus.queued && !i.cancelRequested) {
          next = i;
          break;
        }
      }
      if (next == null) break;
      _activeJobs++;
      next.status = DownloadStatus.resolving;
      notifyListeners();
      final job = next;
      unawaited(() async {
        try {
          await _runJob(job);
        } finally {
          _activeJobs = max(0, _activeJobs - 1);
          _pumpQueue();
        }
      }());
    }
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
      String outPath;
      if (lowerUrl.contains('.m3u8') ||
          lowerUrl.contains('/hls/') ||
          lowerUrl.contains('manifest')) {
        outPath = '${dir.path}/$safeName.ts';
        await _downloadHls(item, url, outPath);
      } else {
        outPath = '${dir.path}/$safeName.mp4';
        await _downloadProgressive(item, url, outPath);
      }

      if (item.cancelRequested) return;
      if (item.status == DownloadStatus.paused) {
        await _persist();
        return;
      }
      if (item.status == DownloadStatus.failed) return;

      if (outPath.toLowerCase().endsWith('.ts')) {
        item.status = DownloadStatus.fusing;
        item.progress = 0.92;
        notifyListeners();
        DownloadNotifier.showProgress(
          jobId: item.id,
          title: item.title,
          qualityLabel: item.quality,
          progress: 92,
          isActive: true,
          bodyText: 'Packaging video (MKV)…',
        );
        final mkvPath = await _remuxTsToMkv(outPath);
        if (mkvPath != null && await File(mkvPath).exists()) {
          try {
            if (await File(outPath).exists()) await File(outPath).delete();
          } catch (_) {}
          outPath = mkvPath;
        }
      }

      try {
        item.status = DownloadStatus.fusing;
        item.progress = 0.96;
        notifyListeners();
        DownloadNotifier.showProgress(
          jobId: item.id,
          title: item.title,
          qualityLabel: item.quality,
          progress: 96,
          isActive: true,
          bodyText: 'Saving subtitles…',
        );
        final sidePath = await _ensureSidecarSubtitle(
          item: item,
          videoPath: outPath,
        );
        if (sidePath != null && await File(sidePath).exists()) {
          item.localSubtitlePath = sidePath;
        }
      } catch (e) {
        debugPrint('Sidecar subtitle skipped: $e');
      }

      if (item.cancelRequested) return;

      final verifiedPath = await _verifyAndRepairVideo(outPath);
      if (verifiedPath == null) {
        throw Exception(
          'Download finished, but the final video container could not be verified.',
        );
      }
      outPath = verifiedPath;

      _stopKeepAlive(item);
      item.status = DownloadStatus.completed;
      item.progress = 1.0;
      item.localPath = outPath;
      item.resetMetrics();
      notifyListeners();
      await _persist();
      DownloadNotifier.showCompleted(
        jobId: item.id,
        title: item.title,
        qualityLabel: item.quality,
      );
    } catch (e) {
      if (item.cancelRequested) return;
      _stopKeepAlive(item);
      item.status = DownloadStatus.failed;
      item.error = e.toString();
      item.resetMetrics();
      notifyListeners();
      await _persist();
    }
  }

  Future<String?> _ensureSidecarSubtitle({
    required DownloadItem item,
    required String videoPath,
  }) async {
    final sidePath = videoPath.replaceAll(RegExp(r'\.[^.]+$'), '.srt');

    try {
      if (await File(sidePath).exists() && await File(sidePath).length() > 32) {
        return sidePath;
      }
    } catch (_) {}

    String? body;

    if (item.subtitleUrl != null && item.subtitleUrl!.trim().isNotEmpty) {
      body = await _fetchSubtitleBody(item.subtitleUrl!, referer: item.referer);
    }

    if (body == null || body.trim().isEmpty) {
      final tmdbId = _extractTmdbId(item.id);
      if (tmdbId != null && tmdbId.isNotEmpty) {
        try {
          final wyzie = WyzieSubtitleService();
          final preferred = await wyzie.fetchPreferred(
            tmdbId: tmdbId,
            season: item.mediaType == 'tv' ? item.season : null,
            episode: item.mediaType == 'tv' ? item.episode : null,
            language: 'en',
          );
          if (preferred != null) {
            body = preferred.body;
          }
          wyzie.dispose();
        } catch (e) {
          debugPrint('Wyzie auto-search failed: $e');
        }
      }
    }

    if (body == null || body.trim().isEmpty) return null;

    if (body.trimLeft().toUpperCase().startsWith('WEBVTT')) {
      body = _vttToSrt(body);
    }
    if (body.isNotEmpty && body.codeUnitAt(0) == 0xFEFF) {
      body = body.substring(1);
    }

    try {
      await File(sidePath).writeAsString(body);
      return sidePath;
    } catch (e) {
      debugPrint('Write sidecar failed: $e');
      return null;
    }
  }

  Future<String?> _fetchSubtitleBody(String url, {String? referer}) async {
    // Local file path (subtitle pre-fetched to disk, e.g. OpenSubtitles).
    // Anything that isn't an http(s) URL is treated as a filesystem path.
    if (!url.toLowerCase().startsWith('http')) {
      try {
        final f = File(url);
        if (await f.exists()) {
          final body = await f.readAsString();
          if (body.trim().isNotEmpty) return body;
        }
      } catch (e) {
        debugPrint('Local subtitle read failed: $e');
      }
      return null;
    }

    try {
      final wyzie = WyzieSubtitleService();
      final fromService = await wyzie.downloadBody(url);
      wyzie.dispose();
      if (fromService != null && fromService.trim().isNotEmpty) {
        return fromService;
      }
    } catch (_) {}

    try {
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/plain, text/vtt, application/x-subrip, */*',
        if (referer != null && referer.isNotEmpty) 'Referer': referer,
      };
      final res = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.body.trim().isEmpty) return null;
      return res.body;
    } catch (e) {
      debugPrint('Subtitle URL fetch failed: $e');
      return null;
    }
  }

  String? _extractTmdbId(String itemId) {
    final m = RegExp(r'^(\d+)').firstMatch(itemId.trim());
    return m?.group(1);
  }

  static String _vttToSrt(String vtt) {
    final lines =
        vtt.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = StringBuffer();
    var index = 1;
    final timeRe = RegExp(
      r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\.(\d{1,3})\s*-->\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\.(\d{1,3})',
    );

    String padMs(String ms) => ms.padRight(3, '0').substring(0, 3);

    for (var i = 0; i < lines.length; i++) {
      final m = timeRe.firstMatch(lines[i]);
      if (m == null) continue;

      final sh = m[1] ?? '00';
      final sm = m[2]!;
      final ss = m[3]!;
      final sms = padMs(m[4]!);
      final eh = m[5] ?? '00';
      final em = m[6]!;
      final es = m[7]!;
      final ems = padMs(m[8]!);

      out.writeln(index++);
      out.writeln(
        '${sh.padLeft(2, '0')}:${sm.padLeft(2, '0')}:$ss,$sms --> '
        '${eh.padLeft(2, '0')}:${em.padLeft(2, '0')}:$es,$ems',
      );

      final textBuf = StringBuffer();
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isNotEmpty) {
        final line = lines[j].trim();
        if (!line.startsWith('NOTE') && !RegExp(r'^\d+$').hasMatch(line)) {
          textBuf.writeln(
            line
                .replaceAll(RegExp(r'<[^>]+>'), '')
                .replaceAll(RegExp(r'\{[^}]+\}'), ''),
          );
        }
        j++;
      }
      out.writeln(textBuf.toString().trim());
      out.writeln();
    }
    return out.toString();
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
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
    };
    try {
      final uri = Uri.parse(mediaUrl);
      if (uri.hasScheme && uri.host.isNotEmpty) {
        headers['Origin'] = '${uri.scheme}://${uri.host}';
      }
    } catch (_) {}
    if (referer != null && referer.isNotEmpty) {
      try {
        final r = Uri.parse(referer);
        if (r.hasScheme && r.host.isNotEmpty) {
          headers['Referer'] = '${r.scheme}://${r.host}/';
          headers['Origin'] = '${r.scheme}://${r.host}';
        } else {
          headers['Referer'] = referer;
        }
      } catch (_) {
        headers['Referer'] = referer;
      }
    }
    return headers;
  }

  List<Map<String, String>> _headerVariants(String mediaUrl, String? referer) {
    final base = _mediaHeaders(mediaUrl, referer);
    final variants = <Map<String, String>>[Map<String, String>.from(base)];

    final desktop = Map<String, String>.from(base)
      ..['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
      ..remove('Sec-Fetch-Dest')
      ..remove('Sec-Fetch-Mode')
      ..remove('Sec-Fetch-Site');
    variants.add(desktop);

    try {
      final media = Uri.parse(mediaUrl);
      if (media.hasScheme && media.host.isNotEmpty) {
        final v3 = Map<String, String>.from(base);
        v3['Origin'] = '${media.scheme}://${media.host}';
        if (referer != null && referer.isNotEmpty) {
          v3['Referer'] = referer;
        }
        variants.add(v3);
      }
    } catch (_) {}

    final minimal = <String, String>{
      'User-Agent': base['User-Agent']!,
      'Accept': '*/*',
    };
    if (referer != null && referer.isNotEmpty) {
      minimal['Referer'] = referer;
    }
    variants.add(minimal);

    return variants;
  }

  Future<Directory> _downloadDir() async {
    Directory root;
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      root = external ?? await getApplicationDocumentsDirectory();
    } else {
      root = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${root.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _downloadProgressive(
    DownloadItem item,
    String url,
    String outPath,
  ) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception('Storage permission denied');
    }

    final file = File(outPath);
    await file.parent.create(recursive: true);

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
              const Duration(seconds: 90),
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

    final sink = file.openWrite(
        mode: existing > 0 && response.statusCode == 206
            ? FileMode.append
            : FileMode.write);
    var lastNotify = DateTime.now();

    try {
      await for (final chunk in response.stream) {
        if (item.cancelRequested || item.pauseRequested) break;
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
      item.client?.close();
    }

    if (item.cancelRequested) return;

    if (item.pauseRequested) {
      return;
    }

    final written = await file.length();
    if (written <= 0) {
      throw Exception('Download finished but file is empty (0 bytes).');
    }

    if (item.totalBytes > 0 && written < item.totalBytes) {
      throw Exception(
        'Progressive download is incomplete: wrote $written of '
        '${item.totalBytes} bytes.',
      );
    }

    item.progress = 1.0;
    item.localPath = outPath;
  }

  Future<void> _downloadHls(
    DownloadItem item,
    String playlistUrl,
    String outPath,
  ) async {
    final client = http.Client();
    item.client = client;

    try {
      item.status = DownloadStatus.downloading;
      notifyListeners();

      final master = await _fetchHlsPlaylist(
        client: client,
        url: playlistUrl,
        item: item,
        isVariant: false,
      );

      var targetPlaylist = master.url;
      var body = master.body;

      if (body.contains('#EXT-X-STREAM-INF')) {
        targetPlaylist = _selectBestHlsVariant(
          targetPlaylist,
          body,
          qualityLabel: item.quality,
        );

        final variant = await _fetchHlsPlaylist(
          client: client,
          url: targetPlaylist,
          item: item,
          isVariant: true,
        );

        targetPlaylist = variant.url;
        body = variant.body;
      }

      final parsed = _parseHlsMediaPlaylist(targetPlaylist, body);
      if (parsed.segments.isEmpty) {
        throw Exception('No video segments found in playlist');
      }

      Uint8List? aesKey;
      if (parsed.keyUri != null) {
        aesKey = await _fetchAesKey(
          client: client,
          keyUri: parsed.keyUri!,
          playlistUrl: targetPlaylist,
          referer: item.referer,
        );
        if (aesKey == null || aesKey.length != 16) {
          throw Exception(
            'Stream is AES-128 encrypted but the decryption key could not be fetched.',
          );
        }
      }

      final totalSegs = parsed.segments.length;
      final segDir = await _hlsSegmentDir(item);
      await segDir.create(recursive: true);

      final existingSizes = <int, int>{};
      await for (final entity in segDir.list()) {
        if (entity is File) {
          final idx = _hlsSegmentIndexFromPath(entity.path);
          if (idx != null && idx < totalSegs) {
            final len = await entity.length();
            if (len > 0) existingSizes[idx] = len;
          }
        }
      }

      var downloadedSegs = existingSizes.length;
      item.totalBytes = 0;
      item.bytesReceived = existingSizes.values.fold(0, (a, b) => a + b);
      item.progress =
          totalSegs > 0 ? (downloadedSegs / totalSegs).clamp(0.0, 1.0) : 0.0;
      notifyListeners();

      var lastNotify = DateTime.now();
      var nextIndex = 0;
      var aborted = false;
      Object? firstError;

      Future<void> worker() async {
        while (true) {
          if (aborted || item.cancelRequested || item.pauseRequested) return;

          int i;
          while (true) {
            if (nextIndex >= totalSegs) return;
            i = nextIndex++;
            if (!existingSizes.containsKey(i)) break;
          }

          final seg = parsed.segments[i];
          final mediaSeq = parsed.mediaSequence + i;

          await _globalSegmentSemaphore.acquire();
          _SegResult r;
          try {
            r = await _fetchAndDecryptSegment(
              client: client,
              seg: seg,
              mediaSequence: mediaSeq,
              aesKey: aesKey,
              explicitIv: parsed.keyIv,
              referer: item.referer,
              index: i,
              total: totalSegs,
            );
          } finally {
            _globalSegmentSemaphore.release();
          }

          if (item.cancelRequested) return;

          if (r.bytes == null || r.bytes!.isEmpty) {
            aborted = true;
            firstError = Exception(
              'Failed to fetch HLS segment ${r.index + 1}/$totalSegs: '
              '${r.error ?? 'empty response'}',
            );
            return;
          }

          await File(_hlsSegmentPath(segDir, i))
              .writeAsBytes(r.bytes!, flush: false);
          existingSizes[i] = r.bytes!.length;
          downloadedSegs++;
          item.recordProgress(item.bytesReceived + r.bytes!.length);
          item.progress = (downloadedSegs / totalSegs).clamp(0.0, 1.0);

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
      }

      await Future.wait(
        List.generate(hlsSegmentConcurrency, (_) => worker()),
      );

      if (item.cancelRequested) return;
      if (firstError != null) throw firstError!;

      if (item.pauseRequested) {
        return;
      }

      if (downloadedSegs != totalSegs) {
        throw Exception(
          'HLS download is incomplete: downloaded $downloadedSegs of '
          '$totalSegs segments.',
        );
      }

      final outFile = File(outPath);
      if (await outFile.exists()) await outFile.delete();
      final sink = outFile.openWrite(mode: FileMode.write);
      try {
        for (var i = 0; i < totalSegs; i++) {
          final segFile = File(_hlsSegmentPath(segDir, i));
          await sink.addStream(segFile.openRead());
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      try {
        await segDir.delete(recursive: true);
      } catch (_) {}

      final written = await outFile.length();
      if (written <= 0) {
        throw Exception(
          'HLS download produced no data (segments=$downloadedSegs).',
        );
      }

      item.progress = 1.0;
      item.localPath = outPath;
    } finally {
      client.close();
    }
  }

  Future<Directory> _hlsSegmentDir(DownloadItem item) async {
    final root = await _downloadDir();
    final safeId = item.id.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return Directory('${root.path}/.segs_$safeId');
  }

  String _hlsSegmentPath(Directory dir, int index) =>
      '${dir.path}/seg_${index.toString().padLeft(6, '0')}.part';

  int? _hlsSegmentIndexFromPath(String path) {
    final name = path.split('/').last;
    final m = RegExp(r'^seg_(\d+)\.part$').firstMatch(name);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Future<_SegResult> _fetchAndDecryptSegment({
    required http.Client client,
    required _HlsSegment seg,
    required int mediaSequence,
    required Uint8List? aesKey,
    required Uint8List? explicitIv,
    required String? referer,
    required int index,
    required int total,
  }) async {
    List<int>? bytes;
    Object? lastError;

    final headerSets = _headerVariants(seg.url, referer);

    for (var attempt = 0; attempt < 6; attempt++) {
      final headers = headerSets[attempt % headerSets.length];
      try {
        final res = await client
            .get(Uri.parse(seg.url), headers: headers)
            .timeout(const Duration(seconds: 60));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          bytes = res.bodyBytes;
          if (bytes.isNotEmpty) break;
          lastError = 'empty body';
        } else {
          lastError = 'HTTP ${res.statusCode}';
          if (res.statusCode == 403 || res.statusCode == 404) continue;
        }
      } catch (e) {
        lastError = e;
      }
      if (attempt < 5) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    if (bytes == null || bytes.isEmpty) {
      return _SegResult(index: index, bytes: null, error: lastError?.toString());
    }

    if (aesKey != null) {
      try {
        final iv = explicitIv ?? _sequenceToIv(mediaSequence);
        bytes = _aes128CbcDecrypt(Uint8List.fromList(bytes), aesKey, iv);
      } catch (e) {
        return _SegResult(
          index: index,
          bytes: null,
          error: 'AES decrypt failed: $e',
        );
      }
    }

    return _SegResult(index: index, bytes: bytes);
  }

  Uint8List _aes128CbcDecrypt(Uint8List cipher, Uint8List key, Uint8List iv) {
    if (key.length != 16) {
      throw ArgumentError('AES-128 key must be 16 bytes');
    }
    if (iv.length != 16) {
      throw ArgumentError('AES IV must be 16 bytes');
    }
    final cipherEngine = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));

    final out = Uint8List(cipher.length);
    var offset = 0;
    while (offset < cipher.length) {
      offset += cipherEngine.processBlock(cipher, offset, out, offset);
    }

    if (out.isEmpty) return out;
    final pad = out.last;
    if (pad > 0 && pad <= 16) {
      var valid = true;
      for (var i = out.length - pad; i < out.length; i++) {
        if (out[i] != pad) {
          valid = false;
          break;
        }
      }
      if (valid) {
        return Uint8List.sublistView(out, 0, out.length - pad);
      }
    }
    return out;
  }

  Uint8List _sequenceToIv(int sequence) {
    final iv = Uint8List(16);
    final bd = ByteData.sublistView(iv);
    bd.setUint64(8, sequence, Endian.big);
    return iv;
  }

  Future<Uint8List?> _fetchAesKey({
    required http.Client client,
    required String keyUri,
    required String playlistUrl,
    required String? referer,
  }) async {
    String resolved = keyUri;
    if (!keyUri.startsWith('http')) {
      resolved = Uri.parse(playlistUrl).resolve(keyUri).toString();
    }

    final headerSets = _headerVariants(resolved, referer);
    for (final headers in headerSets) {
      try {
        final res = await client
            .get(Uri.parse(resolved), headers: headers)
            .timeout(const Duration(seconds: 30));
        if (res.statusCode >= 200 &&
            res.statusCode < 300 &&
            res.bodyBytes.length >= 16) {
          return Uint8List.fromList(res.bodyBytes.sublist(0, 16));
        }
      } catch (e) {
        debugPrint('AES key fetch failed ($resolved): $e');
      }
    }
    return null;
  }

  _ParsedHlsPlaylist _parseHlsMediaPlaylist(String playlistUrl, String body) {
    final base = Uri.parse(playlistUrl);
    final segments = <_HlsSegment>[];
    String? keyUri;
    Uint8List? keyIv;
    var mediaSequence = 0;
    var currentKeyUri = keyUri;
    Uint8List? currentIv = keyIv;

    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        mediaSequence =
            int.tryParse(line.substring('#EXT-X-MEDIA-SEQUENCE:'.length).trim()) ??
                0;
        continue;
      }

      if (line.startsWith('#EXT-X-KEY:')) {
        final attrs = line.substring('#EXT-X-KEY:'.length);
        final method = RegExp(r'METHOD=([^,]+)').firstMatch(attrs)?.group(1);
        if (method == 'NONE') {
          currentKeyUri = null;
          currentIv = null;
          keyUri = null;
          keyIv = null;
        } else if (method == 'AES-128') {
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(attrs);
          if (uriMatch != null) {
            currentKeyUri = uriMatch.group(1);
            keyUri ??= currentKeyUri;
          }
          final ivMatch = RegExp(r'IV=0x([0-9A-Fa-f]+)').firstMatch(attrs);
          if (ivMatch != null) {
            currentIv = _hexToBytes(ivMatch.group(1)!);
            keyIv ??= currentIv;
          } else {
            currentIv = null;
          }
        }
        continue;
      }

      if (line.startsWith('#')) continue;

      final url =
          line.startsWith('http') ? line : base.resolve(line).toString();
      segments.add(_HlsSegment(url: url, keyUri: currentKeyUri, iv: currentIv));
    }

    return _ParsedHlsPlaylist(
      segments: segments,
      keyUri: keyUri,
      keyIv: keyIv,
      mediaSequence: mediaSequence,
    );
  }

  Uint8List _hexToBytes(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'\s'), '');
    final out = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (out.length == 16) return out;
    final iv = Uint8List(16);
    final copy = min(16, out.length);
    iv.setRange(16 - copy, 16, out.sublist(out.length - copy));
    return iv;
  }

  Future<_HlsPlaylistResponse> _fetchHlsPlaylist({
    required http.Client client,
    required String url,
    required DownloadItem item,
    required bool isVariant,
  }) async {
    final candidates = _buildHlsPlaylistCandidates(url);
    final failures = <String>[];

    for (final candidate in candidates) {
      if (item.cancelRequested) {
        throw Exception('HLS download cancelled');
      }

      final headerSets = _headerVariants(candidate, item.referer);

      for (var attempt = 0; attempt < headerSets.length; attempt++) {
        if (item.cancelRequested) {
          throw Exception('HLS download cancelled');
        }
        final headers = headerSets[attempt];
        try {
          final response = await client
              .get(Uri.parse(candidate), headers: headers)
              .timeout(const Duration(seconds: 45));

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final body = response.body;
            if (body.trim().isNotEmpty && body.contains('#EXTM3U')) {
              return _HlsPlaylistResponse(candidate, body);
            }
            failures.add(
              '${isVariant ? 'variant' : 'playlist'} $candidate '
              'HTTP ${response.statusCode} but not valid M3U8',
            );
          } else {
            failures.add(
              '${isVariant ? 'variant' : 'playlist'} $candidate '
              'HTTP ${response.statusCode}',
            );
            if (response.statusCode == 403 || response.statusCode == 404) {
              continue;
            }
          }
        } catch (e) {
          failures.add('$candidate: $e');
        }

        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }

    final kind = isVariant ? 'variant M3U8 playlist' : 'M3U8 playlist';
    throw Exception(
      'Failed to fetch $kind. Tried ${candidates.length} URL candidate(s) '
      'with multiple header sets. ${failures.take(8).join(' | ')}',
    );
  }

  List<String> _buildHlsPlaylistCandidates(String rawUrl) {
    final candidates = <String>[];
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) return;
      candidates.add(trimmed);
    }

    add(rawUrl);

    try {
      final uri = Uri.parse(rawUrl);
      final decoded = Uri.decodeFull(rawUrl);
      if (decoded != rawUrl) add(decoded);

      for (final key in const [
        'url',
        'src',
        'source',
        'file',
        'stream',
        'playlist',
        'm3u8',
      ]) {
        final value = uri.queryParameters[key];
        if (value != null && value.isNotEmpty) {
          add(value);
          try {
            add(Uri.decodeFull(value));
          } catch (_) {}
        }
      }

      final once = Uri.decodeFull(rawUrl);
      final twice = Uri.decodeFull(once);
      if (twice != rawUrl) add(twice);
    } catch (_) {}

    return candidates;
  }

  int? _parseQualityHeight(String? label) {
    if (label == null || label.isEmpty) return null;
    final lower = label.toLowerCase().trim();
    if (lower == 'auto') return null;
    if (lower.contains('4k') || lower.contains('uhd') || lower.contains('2160')) {
      return 2160;
    }
    if (lower.contains('1440') || lower.contains('2k')) return 1440;
    final matches = RegExp(r'(\d{3,4})').allMatches(lower).toList();
    if (matches.isEmpty) return null;
    for (final m in matches.reversed) {
      final h = int.tryParse(m.group(1)!);
      if (h == null) continue;
      if (h == 2160 || h == 1440 || h == 1080 || h == 720 || h == 480 ||
          h == 360 || h == 240) {
        return h;
      }
    }
    return int.tryParse(matches.last.group(1)!);
  }

  /// Exact height match preferred. Falls back to closest only if needed.
  String _selectBestHlsVariant(
    String masterUrl,
    String masterBody, {
    String? qualityLabel,
  }) {
    final lines = masterBody.split('\n');
    final targetH = _parseQualityHeight(qualityLabel);

    String? exactUrl;
    String? closestUrl;
    int closestDiff = 1 << 30;
    int bestBw = -1;
    String? highestUrl;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      final bw = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '') ??
          0;
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

      if (h <= 0 || targetH == null) continue;

      if (h == targetH) {
        if (exactUrl == null || bw > bestBw) {
          exactUrl = next;
        }
        continue;
      }

      final diff = (h - targetH).abs();
      if (diff < closestDiff) {
        closestDiff = diff;
        closestUrl = next;
      }
    }

    return exactUrl ?? closestUrl ?? highestUrl ?? masterUrl;
  }

  void pauseDownload(String id) {
    final item = getById(id);
    if (item == null || item.status != DownloadStatus.downloading) return;
    item.pauseRequested = true;
    item.status = DownloadStatus.paused;
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
    item.pauseRequested = false;
    item.cancelRequested = false;
    item.error = null;
    item.status = DownloadStatus.queued;
    item.resetMetrics();
    notifyListeners();
    _pumpQueue();
  }

  void retryDownload(String id) {
    final item = getById(id);
    if (item == null) return;
    if (item.status != DownloadStatus.failed &&
        item.status != DownloadStatus.paused) {
      return;
    }
    item.pauseRequested = false;
    item.cancelRequested = false;
    item.error = null;
    item.status = DownloadStatus.queued;
    item.resetMetrics();
    notifyListeners();
    _pumpQueue();
  }

  void cancelDownload(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    final item = _items[index];
    item.cancelRequested = true;
    item.client?.close();
    _stopKeepAlive(item);
    DownloadNotifier.cancel(item.id);
    if (item.localPath != null) {
      try {
        final f = File(item.localPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    unawaited(
      _hlsSegmentDir(item).then((dir) async {
        try {
          if (await dir.exists()) await dir.delete(recursive: true);
        } catch (_) {}
      }),
    );
    _items.removeAt(index);
    notifyListeners();
    _pumpQueue();
  }

  Future<String?> _remuxTsToMkv(String tsPath) async {
    try {
      final source = File(tsPath);
      if (!await source.exists() || await source.length() < 1024) {
        return null;
      }

      final mkvPath =
          tsPath.replaceAll(RegExp(r'\.ts$', caseSensitive: false), '.mkv');
      final output = File(mkvPath);
      if (await output.exists()) await output.delete();

      final cmd =
          '-y '
          '-fflags +genpts+igndts '
          '-i "$tsPath" '
          '-map 0:v? -map 0:a? -map 0:s? '
          '-c copy '
          '-avoid_negative_ts make_zero '
          '-max_interleave_delta 0 '
          '-f matroska '
          '"$mkvPath"';

      final session = await FFmpegKit.execute(cmd);
      final code = await session.getReturnCode();

      if (ReturnCode.isSuccess(code) && await _isPlayableContainer(mkvPath)) {
        return mkvPath;
      }

      try {
        if (await output.exists()) await output.delete();
      } catch (_) {}
      return null;
    } catch (e, st) {
      debugPrint('remux error: $e\n$st');
      return null;
    }
  }

  Future<bool> _isPlayableContainer(String path) async {
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() < 1024) {
        return false;
      }

      final session = await FFmpegKit.execute(
        '-v error '
        '-i "$path" '
        '-map 0:v:0? -map 0:a:0? '
        '-f null -',
      );

      return ReturnCode.isSuccess(await session.getReturnCode());
    } catch (e, st) {
      debugPrint('Container verification error: $e\n$st');
      return false;
    }
  }

  Future<String?> _verifyAndRepairVideo(String inputPath) async {
    if (await _isPlayableContainer(inputPath)) {
      return inputPath;
    }

    final input = File(inputPath);
    if (!await input.exists() || await input.length() <= 0) {
      return null;
    }

    final base =
        inputPath.replaceFirst(RegExp(r'\.[^.]+$', caseSensitive: false), '');
    final remuxPath = '${base}_repaired.mkv';
    final reencodePath = '${base}_reencoded.mkv';

    try {
      final remuxFile = File(remuxPath);
      if (await remuxFile.exists()) await remuxFile.delete();

      final remuxCmd =
          '-y '
          '-fflags +genpts+igndts '
          '-i "$inputPath" '
          '-map 0:v? -map 0:a? -map 0:s? '
          '-c copy '
          '-avoid_negative_ts make_zero '
          '-max_interleave_delta 0 '
          '-f matroska '
          '"$remuxPath"';

      final remuxSession = await FFmpegKit.execute(remuxCmd);
      if (ReturnCode.isSuccess(await remuxSession.getReturnCode()) &&
          await _isPlayableContainer(remuxPath)) {
        try {
          if (await input.exists() && input.path != remuxPath) {
            await input.delete();
          }
        } catch (_) {}
        return remuxPath;
      }

      try {
        if (await remuxFile.exists()) await remuxFile.delete();
      } catch (_) {}

      final reencodeFile = File(reencodePath);
      if (await reencodeFile.exists()) await reencodeFile.delete();

      final reencodeCmd =
          '-y '
          '-fflags +genpts+igndts '
          '-i "$inputPath" '
          '-map 0:v? -map 0:a? '
          '-c:v libx264 -preset veryfast -crf 20 '
          '-c:a aac -b:a 192k '
          '-avoid_negative_ts make_zero '
          '-f matroska '
          '"$reencodePath"';

      final reencodeSession = await FFmpegKit.execute(reencodeCmd);
      if (ReturnCode.isSuccess(await reencodeSession.getReturnCode()) &&
          await _isPlayableContainer(reencodePath)) {
        try {
          if (await input.exists()) await input.delete();
        } catch (_) {}
        return reencodePath;
      }

      try {
        if (await reencodeFile.exists()) await reencodeFile.delete();
      } catch (_) {}

      return null;
    } catch (e, st) {
      debugPrint('Video verification/repair error: $e\n$st');
      return null;
    }
  }

  void clearAll() {
    for (final item in List.of(_items)) {
      cancelDownload(item.id);
    }
  }
}