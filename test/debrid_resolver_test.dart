// Debrid instant-resolve tests (resolver + magnet builder).
// SPDX-License-Identifier: GPL-3.0
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feb/services/addon_content_models.dart';
import 'package:feb/services/debrid_models.dart';
import 'package:feb/services/debrid_resolver.dart';
import 'package:feb/services/debrid_settings.dart';

AddonStream _torrent({
  String? infoHash = 'abcdef0123456789abcdef0123456789abcdef01',
  int? fileIdx,
  String? filename,
  int? videoSize,
  String? url,
}) =>
    AddonStream(
      name: 'Best Release 1080p',
      infoHash: infoHash,
      fileIdx: fileIdx,
      url: url,
      sources: const [
        'tracker:udp://tracker.example.com:1337',
        'dht://ignored',
      ],
      filename: filename,
      videoSize: videoSize,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('magnetFromAddonStream', () {
    test('synthesises a magnet from info-hash, filename and trackers', () {
      final magnet = magnetFromAddonStream(_torrent(filename: 'Movie 2024.mkv'))!;
      expect(magnet, startsWith('magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01'));
      expect(magnet, contains('dn=Movie+2024.mkv'));
      expect(magnet, contains(Uri.encodeQueryComponent('udp://tracker.example.com:1337')));
      expect(magnet, isNot(contains('dht:')));
    });

    test('passes through an explicit magnet url', () {
      const magnet = 'magnet:?xt=urn:btih:deadbeef&dn=Explicit';
      final stream = AddonStream(
        name: 'x',
        url: magnet,
        infoHash: null,
      );
      expect(magnetFromAddonStream(stream), magnet);
    });

    test('returns null when there is no hash or magnet', () {
      expect(magnetFromAddonStream(_torrent(infoHash: null)), isNull);
    });
  });

  group('resolveAddonStreamTorrent', () {
    test('resolves a cached torrent through Torbox end-to-end', () async {
      await DebridSettings.instance.setEnabled(true);
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, 'tb-key');

      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/api/torrents/createtorrent') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'torrent_id': 42},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/v1/api/torrents/mylist') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'files': [
                  {
                    'id': 7,
                    'name': 'Movie.2024.1080p.WEB-DL.mkv',
                    'mime': 'video/x-matroska',
                    'size': 2516582400,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/v1/api/torrents/requestdl') {
          expect(request.url.queryParameters['token'], 'tb-key');
          expect(request.url.queryParameters['torrent_id'], '42');
          expect(request.url.queryParameters['file_id'], '7');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': 'https://dl.torbox.app/stream/42/7',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final result = await resolveAddonStreamTorrent(
        stream: _torrent(filename: 'Movie.2024.1080p.WEB-DL.mkv'),
        client: client,
      );

      expect(result.success, isTrue);
      expect(result.url, 'https://dl.torbox.app/stream/42/7');
      expect(result.provider?.id, DebridProviders.torboxId);
      expect(result.filename, 'Movie.2024.1080p.WEB-DL.mkv');
      expect(result.videoSize, 2516582400);
    });

    test('picks the episode file matching S01E02 patterns', () async {
      await DebridSettings.instance.setEnabled(true);
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, 'tb-key');

      final client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/api/torrents/createtorrent') {
          return http.Response(
              jsonEncode({
                'success': true,
                'data': {'torrent_id': 9},
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        if (path == '/v1/api/torrents/mylist') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'files': [
                  {
                    'id': 1,
                    'name': 'Show.S01E01.mkv',
                    'size': 1000000000,
                  },
                  {
                    'id': 2,
                    'name': 'Show.S01E02.mkv',
                    'size': 500000000,
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path == '/v1/api/torrents/requestdl') {
          expect(request.url.queryParameters['file_id'], '2');
          return http.Response(
            jsonEncode({'success': true, 'data': 'https://dl/2'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final result = await resolveAddonStreamTorrent(
        stream: _torrent(filename: 'Show.S01E02.mkv'),
        season: 1,
        episode: 2,
        client: client,
      );
      expect(result.success, isTrue);
      expect(result.url, 'https://dl/2');
      expect(result.filename, 'Show.S01E02.mkv');
    });

    test('reports notConfigured when no provider has a key', () async {
      await DebridSettings.instance.setEnabled(true);
      // Remove any keys leftover from earlier tests.
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, '');
      await DebridSettings.instance.setApiKey(DebridProviders.premiumizeId, '');

      final result = await resolveAddonStreamTorrent(stream: _torrent());
      expect(result.success, isFalse);
      expect(result.failure, DebridResolveFailure.notConfigured);
    });

    test('reports notCached when Torbox rejects an uncached torrent', () async {
      await DebridSettings.instance.setEnabled(true);
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, 'tb-key');

      final client = MockClient((request) async {
        if (request.url.path == '/v1/api/torrents/createtorrent') {
          return http.Response(
            jsonEncode({
              'success': false,
              'data': null,
              'detail': 'Torrent is not cached',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      });

      final result = await resolveAddonStreamTorrent(
        stream: _torrent(),
        client: client,
      );
      expect(result.success, isFalse);
      expect(result.failure, DebridResolveFailure.notCached);
    });

    test('resolves through Premiumize directdl and selects stream_link',
        () async {
      await DebridSettings.instance.setEnabled(true);
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, '');
      await DebridSettings.instance
          .setApiKey(DebridProviders.premiumizeId, 'pm-key');

      final client = MockClient((request) async {
        expect(request.url.host, 'www.premiumize.me');
        expect(request.url.path, '/api/transfer/directdl');
        expect(request.headers['Authorization'], 'Bearer pm-key');
        final body = request.body;
        final form = Uri.splitQueryString(body);
        expect(form['src'], startsWith('magnet:?xt=urn:btih:abcdef0123456789abcdef0123456789abcdef01'));
        return http.Response(
          jsonEncode({
            'status': 'success',
            'content': [
              {
                'path': '/folder/Movie.2024.2160p.mkv',
                'size': 9000000000,
                'stream_link': 'https://stream.premiumize.me/video',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await resolveAddonStreamTorrent(
        stream: _torrent(filename: 'Movie.2024.2160p.mkv'),
        client: client,
      );
      expect(result.success, isTrue);
      expect(result.url, 'https://stream.premiumize.me/video');
      expect(result.provider?.id, DebridProviders.premiumizeId);
      expect(result.videoSize, 9000000000);
    });

    test('does not call providers while debrid is disabled', () async {
      await DebridSettings.instance.setEnabled(false);
      await DebridSettings.instance.setApiKey(DebridProviders.torboxId, 'tb-key');

      final client = MockClient((request) async {
        fail('no provider request should be made when disabled');
      });

      final result = await resolveAddonStreamTorrent(
        stream: _torrent(),
        client: client,
      );
      expect(result.success, isFalse);
      expect(result.failure, DebridResolveFailure.notConfigured);
    });
  });
}
