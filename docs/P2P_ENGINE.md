# FEB P2P / BitTorrent Engine

## Scope

FEB now has an isolated BitTorrent subsystem in `lib/services/p2p_engine.dart`.
It is intentionally separate from the existing HTTP/HLS `DownloadService` so the
current movie/TV download pipeline is not destabilized while P2P is validated.

The engine is based on `dtorrent_task_v2` 0.5.4 (BSD-3-Clause). The library
provides the protocol implementation; FEB owns the application-level lifecycle,
state snapshots, file selection, media prioritization and Flutter-facing API.

## Capabilities

- `.torrent` file ingestion
- Magnet URI parsing and metadata exchange
- BitTorrent v1, v2 and hybrid torrent parsing
- DHT peer discovery
- TCP and uTP peer transport
- Tracker announces, including tracker URLs supplied by magnets
- WebSeed fallback when a torrent supplies web seeds
- Selective file downloading (`so=` / selected file indices)
- File-priority management with automatic media prioritization
- Pause, resume, stop and remove
- Peer count, seeder count, download/upload speed and byte progress
- Persistent engine index plus the underlying torrent client's resumable state
- Video-oriented sequential downloading
- Playback-position-aware sequential scheduling
- Byte-stream access for torrent files
- Torrent v2 SHA-256 piece validation through the underlying client
- WebTorrent-style tracker signalling support supplied by the dependency

## Public API

Use `P2PEngine.instance` from application code.

```dart
final engine = P2PEngine.instance;
await engine.initialize();

final id = await engine.addMagnet(
  magnetUri,
  streaming: true,
);

engine.pauseTask(id);
engine.resumeTask(id);

final snapshot = engine.snapshotFor(id);
final files = engine.filesFor(id);
```

For a `.torrent` file:

```dart
final id = await engine.addTorrentFile(
  torrentPath,
  selectedFileIndices: const [0],
);
```

For sequential playback:

```dart
await engine.startStreaming(id);
engine.setPlaybackPosition(id, bytePosition);
final stats = engine.getSequentialStats(id);
```

## Integration strategy

The first implementation does **not** replace `DownloadService` or alter the
existing HTTP/HLS downloader. This is deliberate. The next integration layer
should map a `P2PTaskSnapshot` into the existing download UI and, for local
playback, hand the completed `primaryFilePath` to the existing offline player.

The streaming path should be connected to the player only after an end-to-end
range/seek test is added, because the player must understand the byte-stream
semantics of the torrent task rather than treating a torrent URI as an ordinary
HTTP URL.

## Legal / product boundary

The engine is a general-purpose P2P transport. It should be used for content
the application and its users are authorized to distribute or download. This
subsystem does not add a piracy index, copyrighted-content search, DRM bypass,
or access-control circumvention.

## Validation checklist

Before merging into `main`:

1. `flutter pub get`
2. `dart format lib/services/p2p_engine.dart test/p2p_engine_test.dart`
3. `flutter analyze`
4. `flutter test test/p2p_engine_test.dart`
5. Device test with a legal/public-domain magnet
6. Pause/resume after process restart
7. Selective-file torrent test
8. Corrupt-piece recovery test
9. Slow-peer / no-peer recovery test
10. Sequential MP4 playback + seek test
11. Android background lifecycle test
12. iOS network lifecycle test
