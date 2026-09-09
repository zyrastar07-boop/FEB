import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:feb/services/addon_manifest_parser.dart';
import 'package:feb/services/addon_transport_urls.dart';

const _manifestUrl = 'https://cinemeta.example/manifest.json';

String _manifest({
  String id = 'com.example.cinemeta',
  String name = 'Cinemeta',
  String? logo,
  Object? resources,
  Object? types,
  Object? idPrefixes,
  Object? catalogs,
  Object? behaviorHints,
}) {
  final parts = <String, Object?>{
    'id': id,
    'name': name,
    'version': '1.0.0',
    'resources': resources ?? ['catalog', 'meta', 'stream'],
    'description': 'Example catalog add-on',
    'logo': ?logo,
    'types': ?types,
    'idPrefixes': ?idPrefixes,
    'catalogs': ?catalogs,
    'behaviorHints': ?behaviorHints,
  };
  return jsonEncode(parts);
}

void main() {
  const parser = AddonManifestParser();

  group('AddonManifestParser', () {
    test('parses a full manifest', () {
      final manifest = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(
          logo: 'logo.png',
          catalogs: [
            {
              'type': 'movie',
              'id': 'top',
              'name': 'Top Movies',
              'extra': [
                {'name': 'genre', 'options': ['Action', 'Drama']},
                {'name': 'search', 'isRequired': true},
              ],
            },
            {'type': 'series', 'id': 'popular'},
          ],
          behaviorHints: {'configurable': true, 'adult': false, 'p2p': true},
        ),
      );

      expect(manifest.id, 'com.example.cinemeta');
      expect(manifest.name, 'Cinemeta');
      expect(manifest.version, '1.0.0');
      expect(manifest.description, 'Example catalog add-on');
      // Relative logo resolves against the manifest directory.
      expect(manifest.logoUrl, 'https://cinemeta.example/logo.png');
      expect(manifest.transportUrl, _manifestUrl);
      expect(manifest.resources.map((r) => r.name),
          ['catalog', 'meta', 'stream']);
      expect(manifest.types, isEmpty);
      expect(manifest.idPrefixes, isEmpty);
      expect(manifest.catalogs, hasLength(2));
      expect(manifest.catalogs.first.type, 'movie');
      expect(manifest.catalogs.first.id, 'top');
      expect(manifest.catalogs.first.name, 'Top Movies');
      expect(manifest.catalogs.first.extra, hasLength(2));
      expect(manifest.catalogs.first.extra.first.name, 'genre');
      expect(manifest.catalogs.first.extra.first.isRequired, isFalse);
      expect(manifest.catalogs.first.extra.first.options,
          ['Action', 'Drama']);
      expect(manifest.catalogs[1].name, 'popular'); // name falls back to id
      expect(manifest.behaviorHints.configurable, isTrue);
      expect(manifest.behaviorHints.p2p, isTrue);
      expect(manifest.behaviorHints.adult, isFalse);
    });

    test('defaults types/idPrefixes onto string resources', () {
      final manifest = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(
          types: ['movie', 'series'],
          idPrefixes: ['tt'],
          resources: ['catalog', {'name': 'meta', 'types': ['series']}],
        ),
      );
      expect(manifest.idPrefixes, ['tt']);
      expect(manifest.types, ['movie', 'series']);
      // String resource inherits top-level types/prefixes…
      expect(manifest.resources[0].types, ['movie', 'series']);
      expect(manifest.resources[0].idPrefixes, ['tt']);
      // …while an object resource overrides types but keeps prefixes.
      expect(manifest.resources[1].types, ['series']);
      expect(manifest.resources[1].idPrefixes, ['tt']);
    });

    test('throws when required fields are missing', () {
      for (final payload in [
        '{"name":"X","version":"1"}',
        '{"id":"x","version":"1"}',
        '{"id":"x","name":"X"}',
        'not json',
        '[]',
      ]) {
        expect(
          () => parser.parse(manifestUrl: _manifestUrl, payload: payload),
          throwsA(isA<FormatException>()),
          reason: 'payload: $payload',
        );
      }
    });

    test('ignores unknown fields and malformed extras', () {
      final manifest = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(
          resources: ['catalog', 42, null],
          behaviorHints: {'unexpected': true, 'configurable': 'yes'},
        ),
      );
      expect(manifest.resources.map((r) => r.name), ['catalog']);
      expect(manifest.behaviorHints.configurable, isFalse);
    });

    test('resolves absolute / protocol-relative / root-relative logos', () {
      final base = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(logo: 'https://cdn.example/x.png'),
      );
      expect(base.logoUrl, 'https://cdn.example/x.png');

      final protocolRelative = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(logo: '//cdn.example/x.png'),
      );
      expect(protocolRelative.logoUrl, 'https://cdn.example/x.png');

      final rootRelative = parser.parse(
        manifestUrl: 'https://cinemeta.example/sub/manifest.json',
        payload: _manifest(logo: '/assets/logo.png'),
      );
      expect(rootRelative.logoUrl, 'https://cinemeta.example/assets/logo.png');

      final data = parser.parse(
        manifestUrl: _manifestUrl,
        payload: _manifest(logo: 'data:image/png;base64,abc'),
      );
      expect(data.logoUrl, 'data:image/png;base64,abc');
    });
  });

  group('addon transport URLs', () {
    test('base URL strips manifest.json', () {
      expect(addonTransportBaseUrl('https://x.example/manifest.json'),
          'https://x.example');
      expect(
          addonTransportBaseUrl('https://x.example/a/manifest.json?k=v'),
          'https://x.example/a');
    });

    test('builds resource URLs with encoded ids and preserved query', () {
      expect(
        buildAddonResourceUrl(
          manifestUrl: 'https://x.example/manifest.json',
          resource: 'catalog',
          type: 'movie',
          id: 'top',
        ),
        'https://x.example/catalog/movie/top.json',
      );
      expect(
        buildAddonResourceUrl(
          manifestUrl: 'https://x.example/manifest.json',
          resource: 'stream',
          type: 'series',
          id: 'tt1234:1:1',
        ),
        'https://x.example/stream/series/tt1234%3A1%3A1.json',
      );
      expect(
        buildAddonResourceUrl(
          manifestUrl: 'https://x.example/m/manifest.json?api=1',
          resource: 'meta',
          type: 'movie',
          id: 'tt 42',
          extraPathSegment: 'season',
        ),
        'https://x.example/m/meta/movie/tt%2042/season.json?api=1',
      );
    });

    test('path encoding keeps unreserved characters', () {
      expect(encodeAddonPathSegment('abc-_.~XYZ012'), 'abc-_.~XYZ012');
      expect(encodeAddonPathSegment('a:b'), 'a%3Ab');
      expect(encodeAddonPathSegment('café'), 'caf%C3%A9');
    });
  });
}
