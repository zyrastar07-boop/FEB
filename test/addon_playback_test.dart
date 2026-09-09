import 'package:flutter_test/flutter_test.dart';
import 'package:feb/services/addon_content_models.dart';
import 'package:feb/services/addon_models.dart';
import 'package:feb/services/addon_playback.dart';

AddonManifest _addon(String id, {List<String> types = const ['movie', 'series']}) {
  return AddonManifest(
    id: id,
    name: id,
    version: '1.0.0',
    transportUrl: 'https://$id.example/manifest.json',
    resources: const [AddonResource(name: 'stream', types: ['movie', 'series'])],
    types: types,
  );
}

String _streamPayload(List<String> urls) {
  final streams = urls
      .map((u) => '{"name": "$u", "url": "$u"}')
      .join(',');
  return '{"streams": [$streams]}';
}

void main() {
  group('candidate content ids', () {
    test('movie prefers imdb then tmdb variants', () {
      final ids = buildAddonContentIdCandidates(
        tmdbId: '603',
        imdbId: 'tt0133093',
        isSeries: false,
      );
      expect(ids, ['tt0133093', 'tmdb:603', '603']);
    });

    test('series episodes append season/episode, bare id last', () {
      final ids = buildAddonContentIdCandidates(
        tmdbId: '1396',
        imdbId: 'tt0903747',
        isSeries: true,
        season: 2,
        episode: 5,
      );
      expect(ids, [
        'tt0903747:2:5',
        'tmdb:1396:2:5',
        '1396:2:5',
        'tt0903747',
        'tmdb:1396',
        '1396',
      ]);
    });

    test('handles missing ids and dedupes', () {
      expect(
        buildAddonContentIdCandidates(
          tmdbId: '603',
          imdbId: null,
          isSeries: false,
        ),
        ['tmdb:603', '603'],
      );
      expect(
        buildAddonContentIdCandidates(
          tmdbId: '  ',
          imdbId: 'tt0133093',
          isSeries: false,
        ),
        ['tt0133093'],
      );
    });
  });

  group('resolution', () {
    test('probes add-ons per candidate and de-duplicates', () async {
      final a = _addon('addonA');
      final b = _addon('addonB');

      Future<String> fetcher(String url, {Map<String, String>? headers}) async {
        // Both add-ons answer with a direct stream when asked with an IMDb
        // id; addonA duplicates its stream across candidates.
        if (url.contains('tt0133093') || url.contains('tt0133093%3A')) {
          return _streamPayload([
            'https://a.example/master.m3u8',
            'https://a.example/master.m3u8',
            'https://b.example/other.mp4',
          ]);
        }
        if (url.contains('tmdb%3A603') || url.contains('%2F603')) {
          return _streamPayload(['https://b.example/onlytmdb.mp4']);
        }
        return '{"streams": []}';
      }

      final sources = await resolveAddonStreamsForContent(
        manifests: [a, b],
        tmdbId: '603',
        imdbId: 'tt0133093',
        mediaType: 'movie',
        skipImdbEnrichment: true,
        fetcher: fetcher,
      );

      expect(sources, hasLength(3));
      // IMDb candidate probed first → a.example/master.m3u8 comes first.
      expect(sources[0].requestedId, 'tt0133093');
      expect(sources[0].addonName, 'addonA');
      // Duplicate across candidates/rounds collapsed into one entry.
      final urls = sources.map((s) => s.stream.playableDirectUrl).toList();
      expect(urls.toSet(), hasLength(3));
      expect(urls, containsAll([
        'https://a.example/master.m3u8',
        'https://b.example/other.mp4',
        'https://b.example/onlytmdb.mp4',
      ]));
    });

    test('returns nothing when no add-on supports the type', () async {
      final movieOnly = AddonManifest(
        id: 'movieOnly',
        name: 'MovieOnly',
        version: '1.0.0',
        transportUrl: 'https://movieonly.example/manifest.json',
        resources: const [AddonResource(name: 'stream', types: ['movie'])],
        types: const ['movie'],
      );
      final sources = await resolveAddonStreamsForContent(
        manifests: [movieOnly],
        tmdbId: '1396',
        mediaType: 'tv',
        skipImdbEnrichment: true,
      );
      expect(sources, isEmpty);
    });

    test('bestPlayableSource picks the first direct url', () {
      final manifest = _addon('a');
      final torrent = AddonStream(
        name: 'Torrent',
        infoHash: 'a' * 40,
      );
      final direct = AddonStream(
        name: 'Hls',
        url: 'https://a.example/x.m3u8',
      );
      final best = bestPlayableSource([
        AddonPlaybackSource(manifest: manifest, stream: torrent, requestedId: 'x'),
        AddonPlaybackSource(manifest: manifest, stream: direct, requestedId: 'x'),
      ]);
      expect(best!.stream.playableDirectUrl, 'https://a.example/x.m3u8');
    });
  });

  group('media type mapping', () {
    test('maps movie/tv to addon types', () {
      expect(addonTypeForMediaType('movie'), 'movie');
      expect(addonTypeForMediaType('tv'), 'series');
      expect(addonTypeForMediaType('TV'), 'series');
    });
  });
}
