import 'package:flutter_test/flutter_test.dart';
import 'package:feb/services/addon_content_models.dart';

const _catalogPayload = '''
{
  "metas": [
    {
      "id": "tt0111161",
      "type": "movie",
      "name": "The Shawshank Redemption",
      "poster": "https://img/p.jpg",
      "background": "https://img/b.jpg",
      "logo": "https://img/l.png",
      "description": "Two imprisoned men bond.",
      "releaseInfo": "1994",
      "imdbRating": "9.3",
      "genres": ["Drama"]
    },
    {
      "id": "tt0903747",
      "type": "series",
      "name": "Breaking Bad",
      "releaseInfo": "2008-2013"
    },
    {"id": "", "type": "movie", "name": "Dropped"}
  ]
}
''';

const _metaPayload = '''
{
  "meta": {
    "id": "tt0903747",
    "type": "series",
    "name": "Breaking Bad",
    "description": "A chemistry teacher turns to crime.",
    "releaseInfo": "2008-2013",
    "imdbRating": "9.5",
    "genres": ["Crime", "Drama"],
    "cast": [
      {"name": "Bryan Cranston", "image": "https://img/cast.jpg"},
      {"name": "Aaron Paul"}
    ],
    "videos": [
      {"id": "1", "season": 1, "episode": 1, "title": "Pilot",
       "overview": "Walt turns 50.", "released": "2008-01-20",
       "thumbnail": "https://img/t1.jpg"},
      {"id": "2", "season": 1, "episode": 2, "title": "Cat's in the Bag…"}
    ]
  }
}
''';

const _streamsPayload = '''
{
  "streams": [
    {
      "name": "1080p",
      "description": "WEB-DL • x264 • DD+5.1",
      "url": "https://cdn.example/master.m3u8",
      "subtitles": [
        {"url": "https://cdn.example/en.vtt", "lang": "en", "name": "English"},
        {"url": "https://cdn.example/fr.vtt", "lang": "fr"}
      ]
    },
    {
      "name": "4K",
      "description": "BLURAY",
      "url": "https://cdn.example/movie.mp4"
    },
    {
      "name": "Torrent",
      "infoHash": "0123456789012345678901234567890123456789",
      "sources": ["tracker:udp://tracker.example:1337"]
    },
    {
      "name": "External",
      "externalUrl": "https://provider.example/watch?x=1"
    },
    {"name": "Broken", "url": ""}
  ]
}
''';

void main() {
  group('content-id helpers', () {
    test('normalizes display types', () {
      expect(normalizeContentType('tv'), 'series');
      expect(normalizeContentType('show'), 'series');
      expect(normalizeContentType('anime'), 'series');
      expect(normalizeContentType('movie'), 'movie');
      expect(normalizeContentType('SERIES'), 'series');
    });

    test('episode stream ids round-trip', () {
      expect(episodeStreamId('tt0903747', 2, 5), 'tt0903747:2:5');
      final parsed = parseEpisodeStreamId('tt0903747:2:5')!;
      expect(parsed.contentId, 'tt0903747');
      expect(parsed.season, 2);
      expect(parsed.episode, 5);
    });

    test('bare ids parse without season/episode', () {
      final parsed = parseEpisodeStreamId('tt0111161')!;
      expect(parsed.contentId, 'tt0111161');
      expect(parsed.season, isNull);
      expect(parsed.episode, isNull);
    });
  });

  group('catalog parsing', () {
    test('parses catalog metas and drops blank ids', () {
      final items = parseCatalogItems(_catalogPayload);
      expect(items, hasLength(2));
      expect(items.first.id, 'tt0111161');
      expect(items.first.name, 'The Shawshank Redemption');
      expect(items.first.type, 'movie');
      expect(items.first.releaseInfo, '1994');
      expect(items.first.imdbRating, '9.3');
      expect(items.first.genres, ['Drama']);
      expect(items.first.isSeries, isFalse);
      expect(items[1].isSeries, isTrue);
      expect(items[1].background, isNull);
    });

    test('handles missing or malformed metas', () {
      expect(parseCatalogItems('{}'), isEmpty);
      expect(parseCatalogItems('{"metas": 42}'), isEmpty);
      expect(parseCatalogItems('not json'), isEmpty);
    });
  });

  group('meta parsing', () {
    test('parses full meta with episodes and cast', () {
      final meta = parseAddonMeta(_metaPayload)!;
      expect(meta.id, 'tt0903747');
      expect(meta.isSeries, isTrue);
      expect(meta.videos, hasLength(2));
      expect(meta.videos.first.displayCode, 'S1E1');
      expect(meta.videos.first.title, 'Pilot');
      expect(meta.videos.first.thumbnail, 'https://img/t1.jpg');
      expect(meta.cast, hasLength(2));
      expect(meta.cast.first.name, 'Bryan Cranston');
      expect(meta.genres, ['Crime', 'Drama']);
    });

    test('returns null when meta is absent or blank id', () {
      expect(parseAddonMeta('{}'), isNull);
      expect(parseAddonMeta('{"meta": {"type": "movie"}}'), isNull);
    });
  });

  group('stream parsing', () {
    test('parses streams and drops empties', () {
      final streams = parseAddonStreams(_streamsPayload);
      expect(streams, hasLength(4)); // broken url-only entry dropped

      final hls = streams.first;
      expect(hls.label, '1080p');
      expect(hls.description, 'WEB-DL • x264 • DD+5.1');
      expect(hls.playableDirectUrl, 'https://cdn.example/master.m3u8');
      expect(hls.isTorrent, isFalse);
      expect(hls.subtitles, hasLength(2));
      expect(hls.subtitles.first.lang, 'en');
      expect(hls.subtitles.first.name, 'English');
    });

    test('mp4 streams are playable, torrents/external are not direct', () {
      final streams = parseAddonStreams(_streamsPayload);
      expect(streams[1].playableDirectUrl, 'https://cdn.example/movie.mp4');

      final torrent = streams[2];
      expect(torrent.isTorrent, isTrue);
      expect(torrent.playableDirectUrl, isNull);
      expect(torrent.sources, hasLength(1));

      final external = streams[3];
      expect(external.isExternalOnly, isTrue);
      expect(external.openExternalUrl, 'https://provider.example/watch?x=1');
      expect(external.playableDirectUrl, isNull);
    });
  });
}
