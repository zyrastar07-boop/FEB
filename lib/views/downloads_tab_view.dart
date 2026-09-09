import 'dart:io';

import 'package:flutter/material.dart';
import '../design/motion.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import '../services/download_service.dart';
import '../services/auth_service.dart';
import '../services/download_error_messages.dart';
import '../design/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/pressable.dart';
import '../screens/custom_player_screen.dart';

// Import your GallerySaverUtil – adjust the path if needed
import '../utils/gallery_saver.dart';

const _gold = AppDesignTokens.gold;

/// Downloads tab view.
class DownloadsTabView extends StatefulWidget {
  const DownloadsTabView({super.key});

  @override
  State<DownloadsTabView> createState() => _DownloadsTabViewState();
}

class _DownloadsTabViewState extends State<DownloadsTabView> {

  /// Tracks which title groups are expanded (key = title).
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    await DownloadService.instance.ensureLoaded();
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _resolveLocalPath(String value) {
    var path = value.trim();

    if (path.length >= 2 &&
        ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'")))) {
      path = path.substring(1, path.length - 1).trim();
    }

    if (path.toLowerCase().startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath(windows: Platform.isWindows);
      } catch (_) {}
    }

    return path;
  }

  String? _getCompletedLocalPath(DownloadItem item) {
    final stored = item.localPath?.trim() ?? '';
    if (stored.isNotEmpty) {
      final resolved = _resolveLocalPath(stored);
      if (resolved.isNotEmpty) return resolved;
    }

    final legacy = item.videoUrl.trim();
    if (legacy.isNotEmpty) {
      final lower = legacy.toLowerCase();
      if (lower.startsWith('file://') ||
          lower.startsWith('/') ||
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(legacy)) {
        return _resolveLocalPath(legacy);
      }
    }

    return null;
  }

  /// Returns a clean, static total-size string (never the live speed).
  /// Prefers totalBytes when known; falls back to sizeLabel.
  String? _staticTotalSize(DownloadItem item) {
    if (item.totalBytes > 0) {
      return _formatBytes(item.totalBytes);
    }
    final label = item.sizeLabel.trim();
    if (label.isNotEmpty) return label;
    return null;
  }

  Future<void> _saveVideoToGallery(DownloadItem item) async {
    HapticFeedback.mediumImpact();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.videos.status;
        if (!status.isGranted) {
          status = await Permission.videos.request();
        }
      }

      final path = _getCompletedLocalPath(item);
      if (path == null || path.isEmpty) {
        _toast('Local video file is unavailable — re-download it');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _toast('Local file missing — re-download and try again');
        return;
      }

      final fileSize = await file.length();
      if (fileSize <= 0) {
        _toast('Downloaded file is empty or corrupted.');
        return;
      }

      final lowerPath = path.toLowerCase();

      // Check if format is supported by system gallery (mp4, mov, avi, etc.)
      final isStandardVideo = lowerPath.endsWith('.mp4') ||
          lowerPath.endsWith('.mov') ||
          lowerPath.endsWith('.avi') ||
          lowerPath.endsWith('.wmv') ||
          lowerPath.endsWith('.3gp');

      if (isStandardVideo) {
        final result = await GallerySaverUtil.saveFile(
          path,
          isVideo: true,
        );

        if (!mounted) return;

        if (result.success) {
          _toast('Saved "${item.title}" to gallery');
        } else {
          _toast(result.errorMessage ?? 'Permission denied or save failed.');
        }
      } else {
        // IMPORTANT: this branch previously read the *entire* video file
        // into memory with `File(path).readAsBytes()` before handing it to
        // FlutterFileDialog.saveFileToDirectory(). For anything beyond a
        // couple hundred MB — which is most downloaded movies/episodes,
        // and *especially* .mkv files (the remux output for HLS downloads)
        // — that spikes memory hard enough that Android just kills the
        // process. That's the crash: the app doesn't show an error, it
        // just vanishes, because the OOM kill happens below Dart/Flutter's
        // ability to catch it.
        //
        // Fix: use FlutterFileDialog.saveFile() with `sourceFilePath`
        // instead of `data`. The plugin copies the file natively (streamed,
        // not buffered into a Dart Uint8List), so memory use stays flat
        // regardless of file size.
        //
        // Trade-off: saveFile() always opens the system "Save As" dialog
        // (no silently-reused cached folder like saveFileToDirectory did),
        // and duplicate-filename handling becomes the OS's job instead of
        // our custom "Already Downloaded!" dialog. That's a fair trade for
        // "doesn't crash on real video files".
        final ext = path.split('.').lastOrNull ?? 'ts';
        final safeTitle = item.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

        String extraInfo = '';
        if (item.mediaType == 'tv' && item.displayLabel.isNotEmpty) {
          extraInfo =
              '_${item.displayLabel.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}';
        } else if (item.quality.isNotEmpty) {
          extraInfo = '_${item.quality}';
        }

        final customFileName = 'Feb_$safeTitle$extraInfo.$ext';

        final savedPath = await FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(
            sourceFilePath: path,
            fileName: customFileName,
          ),
        );

        if (!mounted) return;

        if (savedPath == null) {
          // User cancelled the save dialog — not an error, stay quiet.
          return;
        }

        _toast('Saved "$customFileName"');
      }
    } catch (e) {
      _toast('Failed to save: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final items = DownloadService.instance.items;

        // ---------------------------------------------------------------
        // Group ALL items by title (movies + series treated the same).
        // - 1 item for a title  → normal individual card
        // - 2+ items for a title → one expandable parent card
        // ---------------------------------------------------------------
        final Map<String, List<DownloadItem>> byTitle = {};
        for (final item in items) {
          byTitle.putIfAbsent(item.title, () => []).add(item);
        }

        // Sort items inside each group
        for (final list in byTitle.values) {
          list.sort((a, b) {
            // Prefer displayLabel (S01E05 etc.), then quality, then id
            final labelCmp = a.displayLabel.compareTo(b.displayLabel);
            if (labelCmp != 0) return labelCmp;
            final qualityCmp = a.quality.compareTo(b.quality);
            if (qualityCmp != 0) return qualityCmp;
            return a.id.compareTo(b.id);
          });
        }

        // Most recently added group first
        final titles = byTitle.keys.toList()
          ..sort((a, b) {
            final aLast = byTitle[a]!.last.id;
            final bLast = byTitle[b]!.last.id;
            return bLast.compareTo(aLast);
          });

        if (items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            physics: const BouncingScrollPhysics(),
            children: [
              _empty(
                Icons.download_rounded,
                'No downloads yet',
                'Tap the download icon on any title to save it offline.',
              ),
            ],
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          physics: const BouncingScrollPhysics(),
          itemCount: titles.length + 2,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) return _activeDownloadsSummary(items);
            if (index == titles.length + 1) {
              return Center(
                child: TextButton.icon(
                  onPressed: () {
                    DownloadService.instance.clearAll();
                    _toast('All downloads cleared');
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent, size: 18),
                  label: const Text('Clear all downloads',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              );
            }
            final title = titles[index - 1];
            final group = byTitle[title]!;
            if (group.length == 1) {
              return _buildDownloadTile(group.first);
            }
            return _buildGroup(title, group);
          },
        );
      },
    );
  }

  /// One parent card for a title that has multiple files.
  /// Smooth expand / collapse animation reveals the individual items.
  Widget _buildGroup(String title, List<DownloadItem> group) {
    final isExpanded = _expandedGroups.contains(title);
    final first = group.first;

    final completedCount =
        group.where((e) => e.status == DownloadStatus.completed).length;
    final activeCount = group
        .where((e) =>
            e.status == DownloadStatus.downloading ||
            e.status == DownloadStatus.resolving ||
            e.status == DownloadStatus.fusing)
        .length;

    // Aggregate static total size when possible
    int totalBytesSum = 0;
    bool anyKnown = false;
    for (final e in group) {
      if (e.totalBytes > 0) {
        totalBytesSum += e.totalBytes;
        anyKnown = true;
      }
    }
    final aggregateSize = anyKnown ? _formatBytes(totalBytesSum) : null;

    return AppCard(
      borderRadius: AppDesignTokens.radiusLg,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // ── Header (tappable) ──────────────────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedGroups.remove(title);
                  } else {
                    _expandedGroups.add(title);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        first.posterUrl,
                        width: 54,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 54,
                          height: 78,
                          color: Colors.grey[850],
                          child: const Icon(Icons.movie, color: Colors.white24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _metaChip(
                                '${group.length} file${group.length == 1 ? '' : 's'}',
                                gold: true,
                              ),
                              if (aggregateSize != null) ...[
                                const SizedBox(width: 6),
                                _metaChip(aggregateSize),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (completedCount > 0)
                                Flexible(
                                  child: Text(
                                    '$completedCount completed',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (completedCount > 0 && activeCount > 0)
                                const Text(
                                  '  ·  ',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                              if (activeCount > 0)
                                Flexible(
                                  child: Text(
                                    '$activeCount downloading',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (completedCount == 0 && activeCount == 0)
                                Flexible(
                                  child: Text(
                                    '${group.length} queued / paused',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Smooth rotating chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,                        duration: AppMotion.scaled(context, AppMotion.fast),

                      curve: Curves.easeInOut,
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: Colors.white70,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Smooth expand / collapse of the children ───────────────
          AnimatedSize(
            duration: AppMotion.scaled(context, AppMotion.medium),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Column(
                    children: [
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white12,
                        indent: 12,
                        endIndent: 12,
                      ),
                      ...group.map((item) => Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                            child: _buildDownloadTile(item, isInsideGroup: true),
                          )),
                      const SizedBox(height: 4),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadTile(DownloadItem item, {bool isInsideGroup = false}) {
    final isComplete = item.status == DownloadStatus.completed;
    final isPaused = item.status == DownloadStatus.paused;
    final isFailed = item.status == DownloadStatus.failed;
    final isActive = item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.resolving;

    final staticSize = _staticTotalSize(item);

    final tile = AppCard(
      borderRadius: AppDesignTokens.radiusLg,
      margin: isInsideGroup ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isInsideGroup)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    item.posterUrl,
                    width: 54,
                    height: 78,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 54,
                      height: 78,
                      color: Colors.grey[850],
                      child: const Icon(Icons.movie, color: Colors.white24),
                    ),
                  ),
                )
              else
                // Compact label for nested item
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gold.withValues(alpha: 0.25)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.displayLabel.isNotEmpty
                        ? item.displayLabel
                        : (item.quality.isNotEmpty ? item.quality : 'FILE'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              SizedBox(width: isInsideGroup ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isInsideGroup
                          ? (item.displayLabel.isNotEmpty
                              ? item.displayLabel
                              : (item.quality.isNotEmpty
                                  ? item.quality
                                  : item.title))
                          : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (!isInsideGroup && item.quality.isNotEmpty)
                          _metaChip(item.quality, gold: true),
                        if (isInsideGroup &&
                            item.quality.isNotEmpty &&
                            item.displayLabel.isNotEmpty)
                          _metaChip(item.quality, gold: true),
                        // Static total size – never mixed with speed
                        if (staticSize != null) ...[
                          if ((!isInsideGroup && item.quality.isNotEmpty) ||
                              (isInsideGroup &&
                                  item.quality.isNotEmpty &&
                                  item.displayLabel.isNotEmpty))
                            const SizedBox(width: 6),
                          _metaChip(staticSize),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _statusBadge(item),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailingAction(item, isComplete, isPaused, isFailed, isActive),
            ],
          ),
          if (!isComplete) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: item.progress.clamp(0.0, 1.0),
                ),
                duration: AppMotion.scaled(context, AppMotion.medium),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  color: isFailed
                      ? Colors.redAccent
                      : (isPaused ? Colors.amber : _gold),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${(item.progress * 100).clamp(0, 100).toInt()}%',
                  style: TextStyle(
                    color: isFailed
                        ? Colors.redAccent
                        : (isPaused ? Colors.amber : _gold),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.sizeProgressLabel,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Live speed + ETA – completely separate from total file size
                if (isActive && item.speedBps > 0) ...[
                  Flexible(
                    child: Text(
                      item.speedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (item.etaLabel.isNotEmpty) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Flexible(
                      child: Text(
                        item.etaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            if (isFailed && item.error != null && item.error!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                DownloadErrorMessages.friendly(item.error!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ],
      ),
    );

    if (isInsideGroup) {
      return tile;
    }

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) {
        DownloadService.instance.cancelDownload(item.id);
        _toast('Removed "${item.title}"');
      },
      child: tile,
    );
  }

  Widget _trailingAction(
    DownloadItem item,
    bool isComplete,
    bool isPaused,
    bool isFailed,
    bool isActive,
  ) {
    if (isComplete) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Save to Device/Downloads',
            onPressed: () async {
              final currentUser = AuthService().currentUser;
              final isGuest = currentUser == null || currentUser.isAnonymous;

              if (isGuest) {
                _toast('Please sign in to save downloads.');
                return;
              }

              final localPath = _getCompletedLocalPath(item);
              if (localPath == null || localPath.isEmpty) {
                _toast('No local file found to save');
                return;
              }

              await _saveVideoToGallery(item);
            },
            icon: const Icon(Icons.save_alt_rounded,
                color: Colors.white70, size: 22),
          ),
          const SizedBox(width: 4),
          Pressable(
            onTap: () async {
              final localPath = _getCompletedLocalPath(item);
              if (localPath == null || localPath.isEmpty) {
                _toast(
                    'The downloaded local file is unavailable — re-download it');
                return;
              }

              final localFile = File(localPath);
              if (!await localFile.exists()) {
                _toast('Local video file is missing — re-download it');
                return;
              }

              final stat = await localFile.stat();
              if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
                _toast('Downloaded video file is empty or invalid');
                return;
              }

              if (!mounted) return;
              Navigator.push(
                context,
                PageRouteBuilder(
                  transitionDuration: AppMotion.scaled(context, AppMotion.medium),
                  pageBuilder: (_, _, _) => CustomPlayerScreen(
                    streamUrl: localPath,
                    title: item.title,
                    wisoApiKey: '',
                    tmdbId: item.id.toString(),
                    imdbId: null,
                    mediaType: item.mediaType,
                    season: item.season,
                    episode: item.episode,
                    headers: null,
                    servers: null,
                    isOffline: true,
                    localSubtitlePath: item.localSubtitlePath,
                  ),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              );
            },
            child: const Icon(Icons.play_circle_fill_rounded,
                color: _gold, size: 32),
          ),
        ],
      );
    }
    if (isFailed) {
      return IconButton(
        tooltip: 'Retry',
        onPressed: () {
          HapticFeedback.lightImpact();
          DownloadService.instance.retryDownload(item.id);
          _toast('Retrying "${item.title}"');
        },
        icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
      );
    }
    return IconButton(
      onPressed: () {
        if (isPaused) {
          DownloadService.instance.resumeDownload(item.id);
        } else if (isActive) {
          DownloadService.instance.pauseDownload(item.id);
        }
      },
      icon: Icon(
        isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        color: Colors.white70,
      ),
    );
  }

  /// Compact banner showing how many downloads are running right now and
  /// their combined live throughput. Mostly useful now that several jobs
  /// can genuinely make progress at once (shared segment concurrency) —
  /// without this it wasn't obvious that "handle more downloads at the
  /// same time" was actually doing anything.
  Widget _activeDownloadsSummary(List<DownloadItem> items) {
    final active = items.where((i) =>
        i.status == DownloadStatus.downloading ||
        i.status == DownloadStatus.resolving ||
        i.status == DownloadStatus.fusing);
    final activeCount = active.length;
    if (activeCount == 0) return const SizedBox.shrink();

    final combinedSpeed =
        active.fold<double>(0, (sum, i) => sum + i.speedBps);
    final pausedCount =
        items.where((i) => i.status == DownloadStatus.paused).length;

    String speedLabel(double bps) {
      if (bps <= 0) return '—';
      if (bps >= 1024 * 1024) {
        return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
      }
      if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
      return '${bps.toStringAsFixed(0)} B/s';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_gold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activeCount == 1
                  ? '1 download in progress'
                  : '$activeCount downloads in progress',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (combinedSpeed > 0)
            Text(
              speedLabel(combinedSpeed),
              style: const TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (pausedCount > 0) ...[
            const SizedBox(width: 8),
            Text(
              '· $pausedCount paused',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(DownloadItem item) {
    late final String label;
    late final Color color;
    late final IconData icon;

    switch (item.status) {
      case DownloadStatus.queued:
        label = 'Queued';
        color = Colors.white38;
        icon = Icons.schedule_rounded;
        break;
      case DownloadStatus.resolving:
        label = 'Resolving…';
        color = Colors.lightBlueAccent;
        icon = Icons.travel_explore_rounded;
        break;
      case DownloadStatus.downloading:
        label = 'Downloading';
        color = _gold;
        icon = Icons.downloading_rounded;
        break;
      case DownloadStatus.paused:
        label = 'Paused';
        color = Colors.orangeAccent;
        icon = Icons.pause_circle_outline_rounded;
        break;
      case DownloadStatus.completed:
        label = 'Completed';
        color = Colors.greenAccent;
        icon = Icons.check_circle_outline_rounded;
        break;
      case DownloadStatus.failed:
        label = 'Failed';
        color = Colors.redAccent;
        icon = Icons.error_outline_rounded;
        break;
      case DownloadStatus.fusing:
        label = 'Fusing subtitles…';
        color = _gold;
        icon = Icons.subtitles_rounded;
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String text, {bool gold = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: gold
              ? _gold.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: gold ? _gold : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    final digits = value >= 100 || i == 0 ? 0 : (value >= 10 ? 1 : 2);
    return '${value.toStringAsFixed(digits)} ${units[i]}';
  }

  Widget _empty(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: _gold.withValues(alpha: 0.22),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.06),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: _gold,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
