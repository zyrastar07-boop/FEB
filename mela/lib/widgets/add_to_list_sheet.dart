import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/custom_lists_service.dart';
import '../services/font_service.dart';
import '../services/user_library_service.dart';
import 'new_list_modal.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF121212);

/// Bottom sheet: add/remove a title from Watchlist, My List, and custom lists.
class AddToListSheet extends StatefulWidget {
  final Movie movie;

  const AddToListSheet({super.key, required this.movie});

  static Future<void> show(BuildContext context, Movie movie) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToListSheet(movie: movie),
    );
  }

  @override
  State<AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends State<AddToListSheet> {
  @override
  void initState() {
    super.initState();
    CustomListsService.instance.hydrate();
    UserLibraryService.instance.hydrate();
  }

  void _toast(String msg) {
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
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Add to list',
                    style: FontService.instance.display(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              widget.movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10, height: 1),
          Flexible(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                UserLibraryService.instance,
                CustomListsService.instance,
              ]),
              builder: (context, _) {
                final lib = UserLibraryService.instance;
                final custom = CustomListsService.instance.lists;
                final inWatchlist = lib.isInWatchlistMovie(widget.movie);
                final inMyList = lib.isInMyListMovie(widget.movie);

                return ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 8, 12, bottom + 16),
                  children: [
                    _row(
                      icon: inWatchlist
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_outlined,
                      title: 'Watchlist',
                      subtitle: 'Quick access from Collections',
                      active: inWatchlist,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        final added =
                            await lib.toggleWatchlist(widget.movie);
                        _toast(added
                            ? 'Added to Watchlist'
                            : 'Removed from Watchlist');
                      },
                    ),
                    _row(
                      icon: inMyList
                          ? Icons.playlist_add_check_rounded
                          : Icons.playlist_add_rounded,
                      title: 'My List',
                      subtitle: 'Your personal shortlist',
                      active: inMyList,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        final added = await lib.toggleMyList(widget.movie);
                        _toast(added
                            ? 'Added to My List'
                            : 'Removed from My List');
                      },
                    ),
                    if (custom.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 12, 8, 6),
                        child: Text(
                          'YOUR LISTS',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final list in custom)
                        _row(
                          icon: list.items.any((m) => m.id == widget.movie.id)
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          title: list.name,
                          subtitle: list.description.isEmpty
                              ? '${list.contentCount} titles'
                              : list.description,
                          active: list.items
                              .any((m) => m.id == widget.movie.id),
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final already = list.items
                                .any((m) => m.id == widget.movie.id);
                            if (already) {
                              await CustomListsService.instance
                                  .removeMovie(list.id, widget.movie.id);
                              _toast('Removed from "${list.name}"');
                            } else {
                              await CustomListsService.instance
                                  .addMovie(list.id, widget.movie);
                              _toast('Added to "${list.name}"');
                            }
                          },
                        ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        final created = await NewListModal.show(context);
                        if (created == true && mounted) {
                          final lists = CustomListsService.instance.lists;
                          if (lists.isNotEmpty) {
                            await CustomListsService.instance
                                .addMovie(lists.first.id, widget.movie);
                            _toast('Created list & added title');
                          }
                        }
                      },
                      icon: const Icon(Icons.add_rounded, color: _gold),
                      label: const Text(
                        'Create new list',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? _gold.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? _gold.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: active ? _gold : Colors.white70, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Icon(Icons.check_rounded, color: _gold, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}