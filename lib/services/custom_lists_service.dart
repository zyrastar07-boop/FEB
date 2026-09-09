import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.dart';
import '../models/user_list.dart';

/// Local persistence for user-created lists (no cloud / visibility).
class CustomListsService extends ChangeNotifier {
  static final CustomListsService instance = CustomListsService._();
  CustomListsService._();

  static const _storageKey = 'mela_custom_lists_v1';

  final List<UserList> _lists = [];
  bool _hydrated = false;

  List<UserList> get lists => List.unmodifiable(_lists);

  int get listCount => _lists.length;

  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List;
      _lists
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((e) => UserList.fromJson(Map<String, dynamic>.from(e))),
        );
      notifyListeners();
    } catch (e) {
      debugPrint('[CustomListsService] hydrate failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_lists.map((l) => l.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('[CustomListsService] persist failed: $e');
    }
  }

  Future<UserList> createList({
    required String name,
    String description = '',
  }) async {
    await hydrate();
    final now = DateTime.now();
    final list = UserList(
      id: 'list_${now.millisecondsSinceEpoch}',
      name: name.trim(),
      description: description.trim(),
      items: const [],
      createdAt: now,
      updatedAt: now,
    );
    _lists.insert(0, list);
    await _persist();
    notifyListeners();
    return list;
  }

  Future<void> renameList(String id, String name, {String? description}) async {
    final i = _lists.indexWhere((l) => l.id == id);
    if (i < 0) return;
    _lists[i] = _lists[i].copyWith(
      name: name.trim(),
      description: description?.trim(),
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> deleteList(String id) async {
    _lists.removeWhere((l) => l.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> addMovie(String listId, Movie movie) async {
    final i = _lists.indexWhere((l) => l.id == listId);
    if (i < 0) return;
    final existing = _lists[i].items;
    if (existing.any((m) => m.id == movie.id)) return;
    _lists[i] = _lists[i].copyWith(
      items: [...existing, movie],
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> removeMovie(String listId, int movieId) async {
    final i = _lists.indexWhere((l) => l.id == listId);
    if (i < 0) return;
    _lists[i] = _lists[i].copyWith(
      items: _lists[i].items.where((m) => m.id != movieId).toList(),
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  UserList? getById(String id) {
    try {
      return _lists.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  List<UserList> filtered({
    String query = '',
    String mediaFilter = 'all', // all | movie | tv
    String sort = 'updated', // updated | name | progress | voted
  }) {
    var result = List<UserList>.from(_lists);

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result
          .where((l) =>
              l.name.toLowerCase().contains(q) ||
              l.description.toLowerCase().contains(q))
          .toList();
    }

    if (mediaFilter == 'movie' || mediaFilter == 'tv') {
      result = result.where((l) {
        if (l.items.isEmpty) return true;
        return l.items.any((m) => (m.mediaType) == mediaFilter);
      }).toList();
    }

    switch (sort) {
      case 'name':
        result.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'progress':
        result.sort(
            (a, b) => b.progressPercent.compareTo(a.progressPercent));
        break;
      case 'voted':
        result.sort((a, b) {
          double avg(UserList l) {
            if (l.items.isEmpty) return 0;
            return l.items.fold<double>(0, (s, m) => s + m.voteAverage) /
                l.items.length;
          }
          return avg(b).compareTo(avg(a));
        });
        break;
      case 'updated':
      default:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    return result;
  }
}