import 'package:flutter_test/flutter_test.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:feb/services/p2p_engine.dart';

void main() {
  group('P2PEngine formatting', () {
    test('formats byte counts', () {
      expect(P2PEngine.formatBytes(0), '0 B');
      expect(P2PEngine.formatBytes(1024), '1 KB');
      expect(P2PEngine.formatBytes(1024 * 1024), '1 MB');
      expect(P2PEngine.formatBytes(5 * 1024 * 1024), '5 MB');
    });

    test('formats transfer rates', () {
      expect(P2PEngine.formatBytesPerSecond(0), '0 B/s');
      expect(P2PEngine.formatBytesPerSecond(1024), '1 KB/s');
    });
  });

  group('magnet parsing', () {
    test('accepts a standard BitTorrent magnet', () {
      final magnet = MagnetParser.parse(
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
        '&dn=Example%20Torrent',
      );

      expect(magnet, isNotNull);
      expect(magnet!.infoHashString, '0123456789abcdef0123456789abcdef01234567');
      expect(magnet.displayName, 'Example Torrent');
    });

    test('rejects malformed magnets', () {
      expect(MagnetParser.parse('https://example.com/video'), isNull);
      expect(MagnetParser.parse('magnet:?dn=missing-infohash'), isNull);
    });
  });
}
