import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/iptv_channel_model.dart';

/// Service responsible for downloading and parsing M3U / M3U8 playlists
/// into strongly-typed [IptvChannel] objects.
class IptvParserService {
  static const String defaultPlaylistUrl =
      'https://iptv-org.github.io/iptv/index.m3u';

  /// Downloads the playlist and returns a list of parsed channels.
  /// Throws on network or parsing failures.
  Future<List<IptvChannel>> fetchAndParse({
    String playlistUrl = defaultPlaylistUrl,
  }) async {
    final response = await http
        .get(Uri.parse(playlistUrl))
        .timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download playlist: HTTP ${response.statusCode}',
      );
    }

    return parseM3u(response.body);
  }

  /// Pure parser – works on any M3U string (useful for testing / offline).
  List<IptvChannel> parseM3u(String content) {
    final lines = const LineSplitter().convert(content);
    final channels = <IptvChannel>[];

    String? currentExtInf;
    int index = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        currentExtInf = line;
        continue;
      }

      // Skip other tags
      if (line.startsWith('#')) continue;

      // This is a stream URL
      if (currentExtInf != null && line.startsWith('http')) {
        final channel = _parseExtInf(currentExtInf, line, index);
        if (channel != null) {
          channels.add(channel);
          index++;
        }
        currentExtInf = null;
      }
    }

    return channels;
  }

  IptvChannel? _parseExtInf(String extInf, String streamUrl, int index) {
    // Example:
    // #EXTINF:-1 tvg-id="..." tvg-logo="..." group-title="Sports",Channel Name

    try {
      // Extract attributes
      final attrRegex = RegExp(r'([\w-]+)="([^"]*)"');
      final attrs = <String, String>{};
      for (final match in attrRegex.allMatches(extInf)) {
        attrs[match.group(1)!] = match.group(2)!;
      }

      // Channel name is everything after the last comma
      final commaIndex = extInf.lastIndexOf(',');
      String name = commaIndex != -1
          ? extInf.substring(commaIndex + 1).trim()
          : 'Unknown Channel';

      if (name.isEmpty) name = 'Channel $index';

      final logo = attrs['tvg-logo'];
      final group = attrs['group-title'] ?? 'Uncategorized';
      final tvgId = attrs['tvg-id'];
      final language = attrs['tvg-language'] ?? attrs['language'];
      final country = attrs['tvg-country'] ?? attrs['country'];

      final category = IptvChannel.mapToCategory(group);
      final quality = IptvChannel.inferQuality(name, group);

      // Stable-ish ID
      final id = tvgId?.isNotEmpty == true
          ? tvgId!
          : '${name.hashCode.abs()}_$index';

      return IptvChannel(
        id: id,
        name: name,
        streamUrl: streamUrl.trim(),
        logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
        groupTitle: category, // we store the mapped category
        language: language,
        country: country,
        tvgId: tvgId,
        quality: quality,
        isHealthy: true, // will be updated by validator
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the list of top-level categories used by the UI filter bar.
  static List<String> get topCategories => const [
        'All',
        'Sports',
        'Entertainment',
        'News',
        'Movies',
        'Kids',
        'Music',
        'Documentary',
      ];
}