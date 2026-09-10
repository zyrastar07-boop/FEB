import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// High-level state exposed to the Flutter UI.
enum P2PTaskStatus {
  queued,
  resolvingMetadata,
  downloading,
  paused,
  completed,
  stopped,
  failed,
}

/// Immutable snapshot for a torrent task.
class P2PTaskSnapshot {
  final String id;
  final String name;
  final String source;
  final String savePath;
  final P2PTaskStatus status;
  final double progress;
  final int downloadedBytes;
  final int? totalBytes;
  final double downloadSpeedBps;
  final double uploadSpeedBps;
  final int connectedPeers;
  final int totalPeers;
  final int seeders;
  final String? primaryFilePath;
  final List<P2PFileSnapshot> files;
  final String? error;
  final DateTime updatedAt;

  const P2PTaskSnapshot({
    required this.id,
    required this.name,
    required this.source,
    required this.savePath,
    required this.status,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.downloadSpeedBps,
    required this.uploadSpeedBps,
    required this.connectedPeers,
    required this.totalPeers,
    required this.seeders,
    required this.primaryFilePath,
    required this.files,
    required this.error,
    required this.updatedAt,
  });

  String get progressLabel => '${(progress * 100).clamp(0, 100).toStringAsFixed(1)}%';
  String get downloadSpeedLabel => P2PEngine.formatBytesPerSecond(downloadSpeedBps);
  String get uploadSpeedLabel => P2PEngine.formatBytesPerSecond(uploadSpeedBps);
  String get downloadedLabel => P2PEngine.formatBytes(downloadedBytes);
  String get totalLabel => totalBytes == null ? 'Unknown' : P2PEngine.formatBytes(totalBytes!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'savePath': savePath,
        'status': status.name,
        'progress': progress,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'downloadSpeedBps': downloadSpeedBps,
        'uploadSpeedBps': uploadSpeedBps,
        'connectedPeers': connectedPeers,
        'totalPeers': totalPeers,
        'seeders': seeders,
        'primaryFilePath': primaryFilePath,
        'files': files.map((e) => e.toJson()).toList(),
        'error': error,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class P2PFileSnapshot {
  final int index;
  final String name;
  final String path;
  final int length;
  final int downloadedBytes;
  final double progress;
  final bool completed;

  const P2PFileSnapshot({
    required this.index,
    required this.name,
    required this.path,
    required this.length,
    required this.downloadedBytes,
    required this.progress,
    required this.completed,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'path': path,
        'length': length,
        'downloadedBytes': downloadedBytes,
        'progress': progress,
        'completed': completed,
      };
}

class P2PEngineException implements Exception {
  final String message;
  const P2PEngineException(this.message);

  @override
  String toString() => 'P2PEngineException: $message';
}

/// Torrent/P2P orchestration layer for FEB.
///
/// This service deliberately sits beside DownloadService instead of replacing it.
/// Existing HTTP/HLS downloads keep their current behavior while torrent jobs get
/// their own queue, state, progress, peer metrics, selective-file support and
/// streaming-oriented sequential mode.
///
/// The underlying client is dtorrent_task_v2, a BSD-3-Clause pure-Dart BitTorrent
/// implementation with DHT, TCP/uTP, magnet metadata, v1/v2 torrents, WebSeeds,
/// selected files, resume state and sequential streaming support.
class P2PEngine extends ChangeNotifier {
  static final P2PEngine instance = P2PEngine._internal();
  P2PEngine._internal();

  static const int engineVersion = 1;
  static const Duration _pollInterval = Duration(milliseconds: 750);
  static const Duration _persistDebounce = Duration(milliseconds: 750);

  final Map<String, _P2PTaskRuntime> _tasks = <String, _P2PTaskRuntime>{};
  final Map<String, P2PTaskSnapshot> _snapshots = <String, P2PTaskSnapshot>{};

  Timer? _pollTimer;
  Timer? _persistTimer;
  Future<void>? _initFuture;
  bool _initialized = false;
  Directory? _rootDirectory;

  List<P2PTaskSnapshot> get tasks => _snapshots.values.toList(growable: false);
  bool get isInitialized => _initialized;
  Directory? get rootDirectory => _rootDirectory;

  Future<void> initialize() {
    _initFuture ??= _initialize();
    return _initFuture!;
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    final support = await getApplicationSupportDirectory();
    _rootDirectory = Directory('${support.path}/p2p');
    await _rootDirectory!.create(recursive: true);

    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTasks());
    _initialized = true;
    notifyListeners();
  }

  Future<String> defaultSavePath(String taskId) async {
    await initialize();
    final dir = Directory('${_rootDirectory!.path}/downloads/$taskId');
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Adds a .torrent file and starts it immediately unless [start] is false.
  Future<String> addTorrentFile(
    String torrentPath, {
    String? taskId,
    String? savePath,
    bool start = true,
    bool streaming = false,
    List<int>? selectedFileIndices,
    Map<int, FilePriority>? filePriorities,
  }) async {
    await initialize();
    final file = File(torrentPath);
    if (!await file.exists()) {
      throw P2PEngineException('Torrent file not found: $torrentPath');
    }

    final model = await TorrentModel.parse(torrentPath);
    final id = taskId ?? _stableId('torrent', model.infoHash.toString(), torrentPath);
    return _addModel(
      id: id,
      source: torrentPath,
      model: model,
      savePath: savePath ?? await defaultSavePath(id),
      start: start,
      streaming: streaming,
      selectedFileIndices: selectedFileIndices,
      filePriorities: filePriorities,
    );
  }

  /// Adds a magnet URI. Metadata is fetched from peers before the actual task starts.
  Future<String> addMagnet(
    String magnetUri, {
    String? taskId,
    String? savePath,
    bool start = true,
    bool streaming = false,
    List<int>? selectedFileIndices,
    Map<int, FilePriority>? filePriorities,
    void Function(double progress)? onMetadataProgress,
  }) async {
    await initialize();

    final magnet = MagnetParser.parse(magnetUri);
    if (magnet == null) {
      throw const P2PEngineException('Invalid magnet URI.');
    }

    final id = taskId ?? _stableId('magnet', magnet.infoHashString, magnetUri);
    if (_tasks.containsKey(id)) return id;

    final destination = savePath ?? await defaultSavePath(id);
    final initial = P2PTaskSnapshot(
      id: id,
      name: magnet.displayName ?? magnet.infoHashString,
      source: magnetUri,
      savePath: destination,
      status: P2PTaskStatus.resolvingMetadata,
      progress: 0,
      downloadedBytes: 0,
      totalBytes: null,
      downloadSpeedBps: 0,
      uploadSpeedBps: 0,
      connectedPeers: 0,
      totalPeers: 0,
      seeders: 0,
      primaryFilePath: null,
      files: const <P2PFileSnapshot>[],
      error: null,
      updatedAt: DateTime.now(),
    );
    _snapshots[id] = initial;
    notifyListeners();
    _schedulePersist();

    try {
      final metadata = MetadataDownloader.fromMagnet(magnetUri);
      final completer = Completer<TorrentModel>();
      final listener = metadata.createListener();

      listener.on<MetaDataDownloadProgress>((event) {
        final raw = event.progress;
        final normalized = raw > 1 ? raw / 100 : raw;
        onMetadataProgress?.call(normalized.clamp(0.0, 1.0));
        _snapshots[id] = _snapshots[id]!.copyWithProgress(
          progress: (normalized * 0.05).clamp(0.0, 0.05),
        );
        notifyListeners();
      });

      listener.on<MetaDataDownloadComplete>((event) {
        try {
          final decoded = decode(event.data);
          final map = Map<String, dynamic>.from(decoded as Map);
          final model = TorrentParser.parseFromMap(map);
          if (model == null) {
            completer.completeError(const P2PEngineException('Received invalid torrent metadata.'));
          } else if (!completer.isCompleted) {
            completer.complete(model);
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
        }
      });

      listener.on<MetaDataDownloadFailed>((event) {
        if (!completer.isCompleted) {
          completer.completeError(P2PEngineException(event.error));
        }
      });

      metadata.startDownload();
      final model = await completer.future;
      return _addModel(
        id: id,
        source: magnetUri,
        model: model,
        savePath: destination,
        start: start,
        streaming: streaming,
        selectedFileIndices: selectedFileIndices ?? magnet.selectedFileIndices,
        filePriorities: filePriorities,
        webSeeds: magnet.webSeeds,
        acceptableSources: magnet.acceptableSources,
        announceTrackers: magnet.trackers,
        metadataPeers: metadata.activePeers,
      );
    } catch (error) {
      final message = error.toString().replaceFirst('P2PEngineException: ', '');
      _snapshots[id] = _snapshots[id]!.copyWith(
        status: P2PTaskStatus.failed,
        error: message,
      );
      notifyListeners();
      _schedulePersist();
      rethrow;
    }
  }

  Future<String> _addModel({
    required String id,
    required String source,
    required TorrentModel model,
    required String savePath,
    required bool start,
    required bool streaming,
    List<int>? selectedFileIndices,
    Map<int, FilePriority>? filePriorities,
    List<Uri>? webSeeds,
    List<Uri>? acceptableSources,
    List<Uri>? announceTrackers,
    Iterable<Peer>? metadataPeers,
  }) async {
    if (_tasks.containsKey(id)) return id;

    final destination = Directory(savePath);
    await destination.create(recursive: true);

    final sequentialConfig = streaming ? SequentialConfig.forVideoStreaming() : null;
    final task = TorrentTask.newTask(
      model,
      destination.path,
      streaming,
      webSeeds,
      acceptableSources,
      sequentialConfig,
    );

    if (selectedFileIndices != null && selectedFileIndices.isNotEmpty) {
      task.applySelectedFiles(selectedFileIndices);
    }
    if (filePriorities != null && filePriorities.isNotEmpty) {
      task.setFilePriorities(filePriorities);
    } else {
      task.autoPrioritizeFiles();
    }

    if (metadataPeers != null) {
      for (final peer in metadataPeers) {
        task.addPeer(peer.address, PeerSource.manual, type: peer.type);
      }
    }

    if (announceTrackers != null) {
      final infoHash = _infoHashBytes(model.infoHash);
      if (infoHash != null) {
        for (final tracker in announceTrackers) {
          task.startAnnounceUrl(tracker, infoHash);
        }
      }
    }

    final runtime = _P2PTaskRuntime(
      id: id,
      source: source,
      savePath: destination.path,
      task: task,
      streaming: streaming,
    );
    _tasks[id] = runtime;

    _snapshots[id] = _snapshot(runtime);
    notifyListeners();
    _schedulePersist();

    if (start) {
      await startTask(id);
    }
    return id;
  }

  Future<void> startTask(String id) async {
    final runtime = _requireRuntime(id);
    if (runtime.started) {
      runtime.task.resume();
      _updateSnapshot(runtime, status: P2PTaskStatus.downloading);
      return;
    }

    runtime.started = true;
    runtime.error = null;
    _updateSnapshot(runtime, status: P2PTaskStatus.downloading);

    try {
      await runtime.task.start();
      _updateSnapshot(runtime, status: runtime.task.progress >= 1 ? P2PTaskStatus.completed : P2PTaskStatus.downloading);
    } catch (error) {
      runtime.error = error.toString();
      _updateSnapshot(runtime, status: P2PTaskStatus.failed);
      rethrow;
    }
  }

  void pauseTask(String id) {
    final runtime = _requireRuntime(id);
    runtime.task.pause();
    _updateSnapshot(runtime, status: P2PTaskStatus.paused);
  }

  void resumeTask(String id) {
    final runtime = _requireRuntime(id);
    runtime.task.resume();
    runtime.started = true;
    _updateSnapshot(runtime, status: P2PTaskStatus.downloading);
  }

  Future<void> stopTask(String id, {bool deleteFiles = false}) async {
    final runtime = _requireRuntime(id);
    await runtime.task.stop();
    if (deleteFiles) {
      await runtime.task.fileManager?.delete();
    }
    _updateSnapshot(runtime, status: P2PTaskStatus.stopped);
  }

  Future<void> removeTask(String id, {bool deleteFiles = false}) async {
    final runtime = _tasks.remove(id);
    if (runtime == null) return;

    try {
      await runtime.task.stop();
    } catch (_) {}

    if (deleteFiles) {
      try {
        await runtime.task.fileManager?.delete();
      } catch (_) {}
      try {
        final dir = Directory(runtime.savePath);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }

    _snapshots.remove(id);
    notifyListeners();
    _schedulePersist();
  }

  /// Returns a byte stream for a selected torrent file.
  ///
  /// For video playback, prefer [startStreaming] first when the task was created
  /// with streaming=true. The underlying client supports sequential video mode and
  /// seek-aware piece scheduling.
  Stream<List<int>>? createFileStream(
    String id, {
    int filePosition = 0,
    int? endPosition,
    String? fileName,
  }) {
    final runtime = _requireRuntime(id);
    return runtime.task.createStream(
      filePosition: filePosition,
      endPosition: endPosition,
      fileName: fileName,
    );
  }

  Future<void> startStreaming(String id) async {
    final runtime = _requireRuntime(id);
    if (!runtime.streaming) {
      throw const P2PEngineException('This task was not created in streaming mode.');
    }
    await runtime.task.startStreaming();
  }

  void setPlaybackPosition(String id, int bytePosition) {
    final runtime = _requireRuntime(id);
    if (!runtime.streaming) return;
    runtime.task.setPlaybackPosition(bytePosition);
    _updateSnapshot(runtime);
  }

  SequentialStats? getSequentialStats(String id) {
    final runtime = _requireRuntime(id);
    if (!runtime.streaming) return null;
    return runtime.task.getSequentialStats();
  }

  List<P2PFileSnapshot> filesFor(String id) {
    final runtime = _requireRuntime(id);
    return _filesFor(runtime);
  }

  P2PTaskSnapshot? snapshotFor(String id) => _snapshots[id];

  /// Forces persistence of the engine index. Torrent piece state is handled by
  /// dtorrent_task_v2's own state-file system.
  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistIndex();
  }

  Future<void> disposeTask(String id) async {
    final runtime = _tasks.remove(id);
    if (runtime == null) return;
    await runtime.task.dispose();
    _snapshots.remove(id);
    notifyListeners();
    _schedulePersist();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _persistTimer?.cancel();
    for (final runtime in _tasks.values) {
      unawaited(runtime.task.dispose());
    }
    _tasks.clear();
    _snapshots.clear();
    super.dispose();
  }

  void _pollTasks() {
    if (_tasks.isEmpty) return;

    var changed = false;
    for (final runtime in _tasks.values) {
      final before = _snapshots[runtime.id];
      final after = _snapshot(runtime);
      if (!_snapshotEquivalent(before, after)) {
        _snapshots[runtime.id] = after;
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
      _schedulePersist();
    }
  }

  P2PTaskSnapshot _snapshot(_P2PTaskRuntime runtime) {
    final task = runtime.task;
    final progress = task.progress.clamp(0.0, 1.0);
    final status = runtime.error != null
        ? P2PTaskStatus.failed
        : progress >= 0.999999
            ? P2PTaskStatus.completed
            : task.state == TaskState.paused
                ? P2PTaskStatus.paused
                : task.state == TaskState.stopped && runtime.started
                    ? P2PTaskStatus.stopped
                    : runtime.started
                        ? P2PTaskStatus.downloading
                        : P2PTaskStatus.queued;

    final files = _filesFor(runtime);
    final total = _totalBytes(files);
    final downloaded = task.downloaded ?? files.fold<int>(0, (sum, f) => sum + f.downloadedBytes);

    return P2PTaskSnapshot(
      id: runtime.id,
      name: task.name.isEmpty ? runtime.id : task.name,
      source: runtime.source,
      savePath: runtime.savePath,
      status: status,
      progress: progress,
      downloadedBytes: downloaded,
      totalBytes: total > 0 ? total : null,
      downloadSpeedBps: task.currentDownloadSpeed * 1000,
      uploadSpeedBps: task.uploadSpeed * 1000,
      connectedPeers: task.connectedPeersNumber,
      totalPeers: task.allPeersNumber,
      seeders: task.seederNumber,
      primaryFilePath: _primaryFilePath(files),
      files: files,
      error: runtime.error,
      updatedAt: DateTime.now(),
    );
  }

  List<P2PFileSnapshot> _filesFor(_P2PTaskRuntime runtime) {
    final files = runtime.task.fileManager?.files ?? const <DownloadFile>[];
    return [
      for (var index = 0; index < files.length; index++)
        P2PFileSnapshot(
          index: index,
          name: files[index].originalFileName,
          path: files[index].filePath,
          length: files[index].length,
          downloadedBytes: files[index].downloadedBytes,
          progress: files[index].downloadProgress.clamp(0.0, 1.0),
          completed: files[index].completed,
        ),
    ];
  }

  String? _primaryFilePath(List<P2PFileSnapshot> files) {
    if (files.isEmpty) return null;
    final videos = files.where((file) {
      final name = file.name.toLowerCase();
      return name.endsWith('.mp4') ||
          name.endsWith('.mkv') ||
          name.endsWith('.webm') ||
          name.endsWith('.mov') ||
          name.endsWith('.avi') ||
          name.endsWith('.m4v');
    }).toList();
    final candidates = videos.isNotEmpty ? videos : files;
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first.path;
  }

  int _totalBytes(List<P2PFileSnapshot> files) => files.fold<int>(0, (sum, file) => sum + file.length);

  void _updateSnapshot(
    _P2PTaskRuntime runtime, {
    P2PTaskStatus? status,
  }) {
    final snapshot = _snapshot(runtime);
    if (status == null || snapshot.status == status) {
      _snapshots[runtime.id] = snapshot;
    } else {
      _snapshots[runtime.id] = snapshot.copyWith(status: status);
    }
    notifyListeners();
    _schedulePersist();
  }

  _P2PTaskRuntime _requireRuntime(String id) {
    final runtime = _tasks[id];
    if (runtime == null) throw P2PEngineException('Unknown P2P task: $id');
    return runtime;
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(_persistIndex());
    });
  }

  Future<void> _persistIndex() async {
    final root = _rootDirectory;
    if (root == null) return;
    try {
      final file = File('${root.path}/engine_index.json');
      final payload = {
        'version': engineVersion,
        'tasks': _snapshots.values.map((e) => e.toJson()).toList(),
      };
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(payload));
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('P2PEngine persistence error: $error');
    }
  }

  static String _stableId(String type, String infoHash, String source) {
    final safeHash = infoHash.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '').toLowerCase();
    if (safeHash.isNotEmpty) return 'p2p_${type}_$safeHash';
    return 'p2p_${type}_${source.hashCode.abs()}';
  }

  static List<int>? _infoHashBytes(dynamic infoHash) {
    if (infoHash is List<int>) return infoHash;
    final text = infoHash?.toString() ?? '';
    if (text.length != 40 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) return null;
    return List<int>.generate(
      20,
      (index) => int.parse(text.substring(index * 2, index * 2 + 2), radix: 16),
    );
  }

  static bool _snapshotEquivalent(P2PTaskSnapshot? a, P2PTaskSnapshot b) {
    if (a == null) return false;
    return a.status == b.status &&
        a.progress == b.progress &&
        a.downloadedBytes == b.downloadedBytes &&
        a.totalBytes == b.totalBytes &&
        a.downloadSpeedBps == b.downloadSpeedBps &&
        a.uploadSpeedBps == b.uploadSpeedBps &&
        a.connectedPeers == b.connectedPeers &&
        a.totalPeers == b.totalPeers &&
        a.seeders == b.seeders &&
        a.primaryFilePath == b.primaryFilePath &&
        a.error == b.error &&
        _filesEquivalent(a.files, b.files);
  }

  static bool _filesEquivalent(List<P2PFileSnapshot> a, List<P2PFileSnapshot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.path != right.path ||
          left.downloadedBytes != right.downloadedBytes ||
          left.progress != right.progress ||
          left.completed != right.completed) {
        return false;
      }
    }
    return true;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = value >= 100 || unit == 0 ? 0 : value >= 10 ? 1 : 2;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  static String formatBytesPerSecond(double bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${formatBytes(bytesPerSecond.round())}/s';
  }
}

class _P2PTaskRuntime {
  final String id;
  final String source;
  final String savePath;
  final TorrentTask task;
  final bool streaming;
  bool started;
  String? error;

  _P2PTaskRuntime({
    required this.id,
    required this.source,
    required this.savePath,
    required this.task,
    required this.streaming,
    this.started = false,
  });
}

extension on P2PTaskSnapshot {
  P2PTaskSnapshot copyWith({
    P2PTaskStatus? status,
    String? error,
  }) {
    return P2PTaskSnapshot(
      id: id,
      name: name,
      source: source,
      savePath: savePath,
      status: status ?? this.status,
      progress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      downloadSpeedBps: downloadSpeedBps,
      uploadSpeedBps: uploadSpeedBps,
      connectedPeers: connectedPeers,
      totalPeers: totalPeers,
      seeders: seeders,
      primaryFilePath: primaryFilePath,
      files: files,
      error: error ?? this.error,
      updatedAt: DateTime.now(),
    );
  }

  P2PTaskSnapshot copyWithProgress({required double progress}) {
    return P2PTaskSnapshot(
      id: id,
      name: name,
      source: source,
      savePath: savePath,
      status: status,
      progress: progress,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      downloadSpeedBps: downloadSpeedBps,
      uploadSpeedBps: uploadSpeedBps,
      connectedPeers: connectedPeers,
      totalPeers: totalPeers,
      seeders: seeders,
      primaryFilePath: primaryFilePath,
      files: files,
      error: error,
      updatedAt: DateTime.now(),
    );
  }
}
