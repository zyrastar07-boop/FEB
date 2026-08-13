import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import '../widgets/available_downloads_sheet.dart';

class PsaProviderService {
  static final PsaProviderService instance = PsaProviderService();

  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'application/json',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final String workerBaseUrl;

  PsaProviderService({
    this.workerBaseUrl =
        'https://psa-scraper.mela-media-2026.workers.dev',
  });

  // ============================
  // MAIN FETCH
  // ============================
  Future<List<DownloadOption>> fetchMovieDownloads(String title) async {
    try {
      final cleanTitle = _cleanTitle(title);

      if (workerBaseUrl.isEmpty) return [];

      final url = workerBaseUrl.replaceAll(RegExp(r'/$'), '');

      final res = await _retryRequest(() {
        return _dio.get(
          url,
          queryParameters: {
            // ✅ FIXED PARAM
            'query_term': cleanTitle,
          },
        );
      });

      dev.log('STATUS: ${res.statusCode}');
      dev.log('RAW RESPONSE: ${res.data}');

      if (res.statusCode == 200 && res.data != null) {
        final parsed = _parseYtsResponse(res.data, cleanTitle);

        if (parsed.isEmpty) {
          dev.log('⚠️ No results parsed for: $cleanTitle');
        }

        return parsed;
      }
    } catch (e, stack) {
      dev.log('❌ FETCH ERROR: $e', stackTrace: stack);
    }

    return [];
  }

  // ============================
  // CLEAN TITLE
  // ============================
  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(\d{4}\)'), '')
        .replaceAll(RegExp(r'\d{4}'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ============================
  // PARSER (HARDENED)
  // ============================
  List<DownloadOption> _parseYtsResponse(
      dynamic responseData, String searchTitle) {
    final List<DownloadOption> options = [];
    int idCounter = 1;

    try {
      if (responseData is! Map) return [];

      final root = responseData['data'] ?? responseData;

      if (root is! Map || root['movies'] is! List) return [];

      final movies = root['movies'] as List;

      for (var movie in movies) {
        final String movieTitle =
            movie['title_long'] ?? movie['title'] ?? searchTitle;

        final int year = movie['year'] ?? 0;
        final List torrents = movie['torrents'] ?? [];

        for (var torrent in torrents) {
          final String quality = torrent['quality'] ?? '720p';
          final String type =
              (torrent['type'] ?? 'WEB').toString().toUpperCase();
          final String size = torrent['size'] ?? 'Unknown';
          final String hash = torrent['hash'] ?? '';

          if (hash.isEmpty) continue;

          final fileName =
              '${movieTitle.replaceAll(' ', '.')}.$year.$quality.$type.x264.mkv';

          final magnet =
              'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(fileName)}';

          options.add(
            DownloadOption(
              id: 'yts_${idCounter++}',
              fileName: fileName,
              quality: quality,
              codec: 'x264',
              source: type.contains('BLURAY') ? 'BluRay' : 'WEB-DL',
              sizeLabel: size,
              durationLabel: 'Full Movie',
              isBest: quality == '1080p',
              language: 'EN',
              streamUrl: magnet,
            ),
          );
        }
      }
    } catch (e) {
      dev.log('❌ PARSE ERROR: $e');
    }

    return options;
  }

  // ============================
  // RETRY FIXED
  // ============================
  Future<Response> _retryRequest(
    Future<Response> Function() request, {
    int retries = 2,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        return await request();
      } catch (e) {
        if (attempt >= retries) rethrow;
        attempt++;
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }
}