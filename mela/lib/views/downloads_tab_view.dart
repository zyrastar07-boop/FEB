import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/download_service.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/pressable.dart';
import '../screens/custom_player_screen.dart'; // Import the custom player

const _gold = Color(0xFFD4AF37);

enum _DownloadSort { recent, nameAZ }

/// Downloads tab view.
class DownloadsTabView extends StatefulWidget {
  const DownloadsTabView({super.key});

  @override
  State<DownloadsTabView> createState() => _DownloadsTabViewState();
}

class _DownloadsTabViewState extends State<DownloadsTabView> {
  String _searchQuery = '';
  _DownloadSort _sortMode = _DownloadSort.recent;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final items = DownloadService.instance.items;
        var filtered = items.where((i) {
          if (_searchQuery.isEmpty) return true;
          return i.title.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        if (_sortMode == _DownloadSort.nameAZ) {
          filtered.sort((a, b) => a.title.compareTo(b.title));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          physics: const BouncingScrollPhysics(),
          children: [
            if (items.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search downloads',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Colors.white38, size: 20),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_DownloadSort>(
                    color: const Color(0xFF1A1A1A),
                    icon: const Icon(Icons.sort_rounded, color: Colors.white70),
                    onSelected: (v) => setState(() => _sortMode = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _DownloadSort.recent,
                        child: Text('Recently added',
                            style: TextStyle(color: Colors.white)),
                      ),
                      PopupMenuItem(
                        value: _DownloadSort.nameAZ,
                        child: Text('Name A–Z',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (items.isEmpty)
              _empty(
                Icons.download_rounded,
                'No downloads yet',
                'Tap the download icon on any title to save it offline.',
              )
            else if (filtered.isEmpty)
              _empty(
                Icons.search_off_rounded,
                'No matches',
                'Try a different search term.',
              )
            else ...[
              ...filtered.map(_buildDownloadTile),
              const SizedBox(height: 8),
              Center(
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
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDownloadTile(DownloadItem item) {
    final isComplete = item.status == DownloadStatus.completed;
    final isPaused = item.status == DownloadStatus.paused;
    final isFailed = item.status == DownloadStatus.failed;
    final isActive = item.status == DownloadStatus.downloading ||
        item.status == DownloadStatus.resolving;

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
      child: LiquidGlassContainer(
        borderRadius: 16,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Quality · size badge row
                      Row(
                        children: [
                          _metaChip(
                            item.mediaType == 'tv'
                                ? item.displayLabel
                                : item.quality,
                            gold: true,
                          ),
                          if (item.totalBytes > 0 ||
                              item.sizeLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _metaChip(
                              item.totalBytes > 0
                                  ? _formatBytes(item.totalBytes)
                                  : item.sizeLabel,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Status badge
                      _statusBadge(item),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _trailingAction(item, isComplete, isPaused, isFailed, isActive),
              ],
            ),
            // Progress + metrics (only while not complete)
            if (!isComplete) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  color: isFailed ? Colors.redAccent : _gold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${(item.progress * 100).clamp(0, 100).toInt()}%',
                    style: TextStyle(
                      color: isFailed ? Colors.redAccent : _gold,
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isActive && item.speedBps > 0) ...[
                    Text(
                      item.speedLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.etaLabel.isNotEmpty) ...[
                      const Text(
                        ' · ',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      Text(
                        item.etaLabel,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              if (isFailed && item.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  item.error!,
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
      ),
    );
  }

  // --- FIXED: Now uses item.id instead of item.tmdbId, and safe fallbacks ---
  Widget _trailingAction(
    DownloadItem item,
    bool isComplete,
    bool isPaused,
    bool isFailed,
    bool isActive,
  ) {
    if (isComplete) {
      return Pressable(
        onTap: () {
          if (item.videoUrl.isEmpty) {
            _toast('No local file found');
            return;
          }
          Navigator.push(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 340),
              pageBuilder: (_, _, _) => CustomPlayerScreen(
                streamUrl: item.videoUrl, // Local file path (e.g. file:///)
                title: item.title,
                wisoApiKey: '', // Empty for offline
                tmdbId: item.id.toString() ?? '', // ✅ Uses item.id
                imdbId: null,
                mediaType: item.mediaType ?? 'movie', // ✅ Safe fallback
                season: item.season ?? 1,            // ✅ Safe fallback
                episode: item.episode ?? 1,          // ✅ Safe fallback
                headers: null,
                servers: null,
                isOffline: true, // Tells player to hide web-based settings
              ),
              transitionsBuilder: (_, animation, _, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          );
        },
        child: const Icon(Icons.play_circle_fill_rounded,
            color: _gold, size: 32),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: gold
            ? _gold.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: gold ? _gold : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.bold,
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