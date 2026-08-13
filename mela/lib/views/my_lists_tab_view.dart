import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../models/user_list.dart';
import '../screens/list_detail_screen.dart';
import '../services/custom_lists_service.dart';
import '../services/user_library_service.dart';
import '../widgets/stacked_list_card.dart';

/// "My Lists" tab: pinned Watchlist + Finished, then custom lists.
class MyListsTabView extends StatefulWidget {
  final String searchQuery;
  final String mediaFilter; // all | movie | tv
  final String sortMode; // updated | name | progress | voted

  const MyListsTabView({
    super.key,
    this.searchQuery = '',
    this.mediaFilter = 'all',
    this.sortMode = 'updated',
  });

  @override
  State<MyListsTabView> createState() => _MyListsTabViewState();
}

class _MyListsTabViewState extends State<MyListsTabView> {
  @override
  void initState() {
    super.initState();
    CustomListsService.instance.hydrate();
  }

  void _openList({
    required String title,
    required String description,
    required List<Movie> items,
    required bool system,
    String? listId,
  }) {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, _, _) => ListDetailScreen(
          title: title,
          description: description,
          items: items,
          isSystemList: system,
          listId: listId,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  List<String> _postersOf(List<Movie> movies) {
    final urls = <String>[];
    for (final m in movies) {
      if (urls.length >= 5) break;
      final url = _posterUrl(m);
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  String _posterUrl(Movie m) {
    try {
      final dynamic d = m;
      if (d.posterUrl is String && (d.posterUrl as String).isNotEmpty) {
        return d.posterUrl as String;
      }
      final path = d.posterPath;
      if (path is String && path.isNotEmpty) {
        if (path.startsWith('http')) return path;
        return 'https://image.tmdb.org/t/p/w342$path';
      }
    } catch (_) {}
    return '';
  }

  bool _matchesQuery(String title, String description) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q);
  }

  List<Movie> _filterMedia(List<Movie> items) {
    if (widget.mediaFilter == 'all') return items;
    return items.where((m) => m.mediaType == widget.mediaFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        UserLibraryService.instance,
        CustomListsService.instance,
      ]),
      builder: (context, _) {
        final watchlist = UserLibraryService.instance.watchlist;
        final finished = UserLibraryService.instance.watched;
        final custom = CustomListsService.instance.filtered(
          query: widget.searchQuery,
          mediaFilter: widget.mediaFilter,
          sort: widget.sortMode,
        );

        final showWatchlist = _matchesQuery('Watchlist', 'Saved for later');
        final showFinished =
            _matchesQuery('Finished', 'Titles you have watched');

        final children = <Widget>[];

        if (showWatchlist) {
          final items = _filterMedia(watchlist);
          children.add(
            StackedListCard(
              title: 'Watchlist',
              description: 'Titles you saved to watch later.',
              posterUrls: _postersOf(items),
              contentCount: items.length,
              watchedCount: 0,
              lastEdited: DateTime.now(),
              pinned: true,
              onTap: () => _openList(
                title: 'Watchlist',
                description: 'Titles you saved to watch later.',
                items: items,
                system: true,
              ),
            ),
          );
        }

        if (showFinished) {
          final items = _filterMedia(finished);
          children.add(
            StackedListCard(
              title: 'Finished',
              description: 'Titles you have marked as watched.',
              posterUrls: _postersOf(items),
              contentCount: items.length,
              watchedCount: items.length,
              lastEdited: DateTime.now(),
              pinned: true,
              onTap: () => _openList(
                title: 'Finished',
                description: 'Titles you have marked as watched.',
                items: items,
                system: true,
              ),
            ),
          );
        }

        for (final UserList list in custom) {
          children.add(
            StackedListCard(
              title: list.name,
              description: list.description,
              posterUrls: list.posterUrls,
              contentCount: list.contentCount,
              watchedCount: list.watchedCount,
              lastEdited: list.updatedAt,
              onTap: () => _openList(
                title: list.name,
                description: list.description,
                items: list.items,
                system: false,
                listId: list.id,
              ),
            ),
          );
        }

        if (children.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_bookmark_outlined,
                      color: Colors.white24, size: 48),
                  SizedBox(height: 14),
                  Text(
                    'No lists yet',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Tap + to create your first collection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          physics: const BouncingScrollPhysics(),
          children: children,
        );
      },
    );
  }
}