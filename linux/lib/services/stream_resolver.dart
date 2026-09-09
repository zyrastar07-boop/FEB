import 'package:http/http.dart' as http;

class StreamResolver {
  /// Extracts the direct .m3u8 stream link from an embed URL
  static Future<String?> getDirectStreamUrl(String embedUrl) async {
    try {
      final response = await http.get(
        Uri.parse(embedUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': embedUrl,
        },
      );

      if (response.statusCode == 200) {
        final body = response.body;

        final RegExp streamRegExp = RegExp(
          r'(?:(?:https?:)?//[^\s"' "'" r'<>]+\.(?:m3u8|mp4)(?:\?[^\s"' "'" r'<>]*)?)',
          caseSensitive: false,
        );

        final match = streamRegExp.firstMatch(body);
        if (match != null) {
          var url = match.group(0);
          if (url != null && url.startsWith('//')) {
            url = 'https:$url';
          }
          return url;
        }
      }
    } catch (e) {
      print("Stream extraction error: $e");
    }
    return null;
  }
}