import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import 'download_notifier.dart';

enum DownloadStatus { downloading, paused, completed, failed }

class DownloadItem {
  final String id;
  final String title;
  final String posterUrl;
  final String videoUrl;
  final String quality;
  final String codec;
  final String sizeLabel;
  double progress; // 0.0 to 1.0
  DownloadStatus status;
  
  StreamSubscription? _subscription;

  DownloadItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.videoUrl,
    required this.quality,
    required this.codec,
    required this.sizeLabel,
    this.progress = 0.0,
    this.status = DownloadStatus.downloading,
  });
}

class DownloadService extends ChangeNotifier {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal();

  final List<DownloadItem> _items = [];
  List<DownloadItem> get items => List.unmodifiable(_items);

  Future<void> enqueueDownload({
    required Movie movie,
    required String videoUrl,
    required String quality,
    required String codec,
    required String sizeLabel,
  }) async {
    final id = movie.id.toString();
    
    if (_items.any((i) => i.id == id && i.status == DownloadStatus.downloading)) {
      return;
    }

    _items.removeWhere((i) => i.id == id);

    final item = DownloadItem(
      id: id,
      title: movie.title,
      posterUrl: movie.posterPath ?? '',
      videoUrl: videoUrl,
      quality: quality,
      codec: codec,
      sizeLabel: sizeLabel,
      progress: 0.0,
      status: DownloadStatus.downloading,
    );

    _items.insert(0, item);
    notifyListeners();

    _startFileDownload(item);
  }

  Future<void> _startFileDownload(DownloadItem item) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${item.id}_${item.quality}.mp4';
      final file = File(filePath);

      // Fallback simulation if URL is placeholder/empty
      if (item.videoUrl.isEmpty || !item.videoUrl.startsWith('http')) {
        _simulateDownload(item, file);
        return;
      }

      final request = http.Request('GET', Uri.parse(item.videoUrl));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final totalBytes = response.contentLength ?? 1024 * 1024 * 50;
        int receivedBytes = 0;
        final sink = file.openWrite();
        final completer = Completer<void>();

        item._subscription = response.stream.listen(
          (chunk) {
            if (item.status == DownloadStatus.paused) return;
            sink.add(chunk);
            receivedBytes += chunk.length;
            
            final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            item.progress = progress;
            notifyListeners();

            DownloadNotifier.showProgress(
              jobId: item.id,
              title: item.title,
              qualityLabel: item.quality,
              progress: (progress * 100).toInt(),
              isActive: true,
            );
          },
          onDone: () async {
            await sink.close();
            item.status = DownloadStatus.completed;
            item.progress = 1.0;
            notifyListeners();
            await DownloadNotifier.showCompleted(
              jobId: item.id,
              title: item.title,
              qualityLabel: item.quality,
            );
            completer.complete();
          },
          onError: (e) async {
            await sink.close();
            item.status = DownloadStatus.failed;
            notifyListeners();
            completer.completeError(e);
          },
          cancelOnError: true,
        );

        await completer.future;
      } else {
        throw Exception('Server responded with status code ${response.statusCode}');
      }
    } catch (e) {
      item.status = DownloadStatus.failed;
      notifyListeners();
    }
  }

  void _simulateDownload(DownloadItem item, File file) async {
    int simulatedProgress = (item.progress * 100).toInt();
    
    Timer.periodic(const Duration(milliseconds: 350), (timer) async {
      if (item.status != DownloadStatus.downloading) {
        timer.cancel();
        return;
      }

      simulatedProgress += 6;
      if (simulatedProgress >= 100) {
        simulatedProgress = 100;
        timer.cancel();
        item.status = DownloadStatus.completed;
        item.progress = 1.0;
        notifyListeners();
        
        await DownloadNotifier.showCompleted(
          jobId: item.id,
          title: item.title,
          qualityLabel: item.quality,
        );
      } else {
        item.progress = simulatedProgress / 100.0;
        notifyListeners();

        await DownloadNotifier.showProgress(
          jobId: item.id,
          title: item.title,
          qualityLabel: item.quality,
          progress: simulatedProgress,
          isActive: true,
        );
      }
    });
  }

  void pauseDownload(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = _items[index];
      item.status = DownloadStatus.paused;
      item._subscription?.pause();
      notifyListeners();
      DownloadNotifier.showProgress(
        jobId: item.id,
        title: item.title,
        qualityLabel: item.quality,
        progress: (item.progress * 100).toInt(),
        isActive: false,
        bodyText: 'Paused',
      );
    }
  }

  void resumeDownload(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = _items[index];
      item.status = DownloadStatus.downloading;
      item._subscription?.resume();
      notifyListeners();
      _startFileDownload(item);
    }
  }

  void clearAll() {
    for (var item in _items) {
      item._subscription?.cancel();
      DownloadNotifier.cancel(item.id);
    }
    _items.clear();
    notifyListeners();
  }
}