import 'package:dio/dio.dart';
import 'package:html/parser.dart' as hp;
import 'dart:developer' as dev;
import '../widgets/available_downloads_sheet.dart'; // Ensure correct path to your DownloadOption

class PaheProviderService {
  static final PaheProviderService instance = PaheProviderService._();
  PaheProviderService._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://pahe.ink', // Update this if the active domain changes
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  Future<List<DownloadOption>> fetchMovieDownloads(String title) async {
    List<DownloadOption> options = [];
    
    try {
      dev.log('Scraping Pahe for: $title');
      
      // Step 1: Search for the movie
      final searchResponse = await _dio.get('/', queryParameters: {'s': title});
      if (searchResponse.statusCode != 200) return options;

      final doc = hp.parse(searchResponse.data);
      
      // Step 2: Find the matching movie post
      final titleElement = doc.querySelector('.post-box-title > a');
      if (titleElement == null) return options;
      
      final postUrl = titleElement.attributes['href'];
      if (postUrl == null || postUrl.isEmpty) return options;

      // Step 3: Fetch the dedicated post page
      final postResponse = await _dio.get(postUrl);
      final postDoc = hp.parse(postResponse.data);

      // Step 4: Extract the download block content
      final contentBlocks = postDoc.querySelectorAll('.entry-content, .box-inner-block');
      
      String currentQuality = '720p';
      String currentCodec = 'x264';
      String currentSize = 'Unknown';

      for (var block in contentBlocks) {
        for (var element in block.children) {
          final text = element.text.toLowerCase();

          // Detect quality headers (e.g., "720p WEB-DL - 800MB")
          if (text.contains('480p') || text.contains('720p') || text.contains('1080p') || text.contains('2160p')) {
            if (text.contains('480p')) currentQuality = '480p';
            if (text.contains('720p')) currentQuality = '720p';
            if (text.contains('1080p')) currentQuality = '1080p';
            if (text.contains('2160p')) currentQuality = '2160p';

            currentCodec = (text.contains('x265') || text.contains('hevc')) ? 'x265' : 'x264';

            // Extract the file size using Regex
            final sizeMatch = RegExp(r'(\d+(?:\.\d+)?\s*[MG]B)', caseSensitive: false).firstMatch(text);
            if (sizeMatch != null) {
              currentSize = sizeMatch.group(1)!.toUpperCase();
            } else {
              currentSize = 'Unknown';
            }
          }

          // Step 5: Extract the actual download buttons mapping to the current quality
          final links = element.querySelectorAll('a.shortc-button, a[href]');
          for (var link in links) {
            final hostName = link.text.trim();
            final url = link.attributes['href'] ?? '';

            // Filter for preferred file hosts
            if (url.isNotEmpty && (hostName.toLowerCase().contains('pixel') || 
                                   hostName.toLowerCase().contains('mega') || 
                                   hostName.toLowerCase().contains('drive'))) {
              options.add(
                DownloadOption(
                  id: 'pahe_${options.length}_${DateTime.now().millisecondsSinceEpoch}',
                  fileName: '${title.replaceAll(' ', '.')}.$currentQuality.$currentCodec',
                  quality: currentQuality,
                  codec: currentCodec,
                  source: 'Pahe ($hostName)',
                  sizeLabel: currentSize,
                  durationLabel: 'N/A', 
                  streamUrl: url, 
                  hasSubtitles: true, // Generally pre-muxed on these releases
                )
              );
            }
          }
        }
      }
    } catch (e) {
      dev.log('Pahe Scraper Error: $e');
    }

    return options;
  }
}