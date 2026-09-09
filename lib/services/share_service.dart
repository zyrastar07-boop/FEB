import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie.dart';

/// ShareService — central place for "share this thing on FEB" copy.
///
/// Every share button (profile app-share, detail title-share, list share, etc.)
/// goes through here so the wording stays consistent and the deep-link format
/// is owned in one place.
///
/// The current behaviour is clipboard-based (the rest of the app already
/// uses Clipboard.setData + a SnackBar). If a future platform wants a true
/// OS share sheet, only this file changes.
class ShareService {
  ShareService._();

  static const String _appBaseUrl = 'https://feb.app';

  /// Builds a slug suitable for the share URL path.
  /// "Inception" → "inception", "Mr. & Mrs. Smith" → "mr-mrs-smith".
  static String slugifyTitle(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'title';
    final lower = s.toLowerCase();
    final cleaned = StringBuffer();
    for (final ch in lower.codeUnits) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[a-z0-9]').hasMatch(c)) {
        cleaned.write(c);
      } else if (c == ' ' || c == '-' || c == '_') {
        cleaned.write('-');
      }
    }
    final collapsed = cleaned.toString().replaceAll(RegExp(r'-+'), '-');
    return collapsed.replaceAll(RegExp(r'^-|-$'), '').isEmpty
        ? 'title'
        : collapsed.replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Deep-link to a title's detail page on the FEB app.
  static String titleDeepLink(Movie movie) {
    final slug = slugifyTitle(movie.title);
    return '$_appBaseUrl/watch/$slug/${movie.id}';
  }

  /// Deep-link to a custom list.
  static String listDeepLink(String listId) =>
      '$_appBaseUrl/list/$listId';

  /// Deep-link to the app's install landing page.
  static String appDeepLink() => '$_appBaseUrl/download';

  // ─── Formatters — every share message goes through one of these ────────

  /// "Watch Inception on FEB — https://feb.app/watch/inception/27205"
  ///
  /// Used by the detail screen's share button.
  static String forTitle(Movie movie) {
    return 'Watch ${movie.title} on FEB — ${titleDeepLink(movie)}';
  }

  /// "Watch my Inception list on FEB — https://feb.app/list/{id}"
  static String forList({
    required String listTitle,
    required String listId,
  }) {
    final safeTitle = listTitle.trim().isEmpty ? 'list' : listTitle.trim();
    return 'Watch my "$safeTitle" list on FEB — ${listDeepLink(listId)}';
  }

  /// "Get FEB — https://feb.app/download"
  ///
  /// Used by the profile screen's app-share button.
  static String forApp() => 'Get FEB — $appDeepLink';

  // ─── Clipboard actions ────────────────────────────────────────────────

  /// Copies [text] to the clipboard and shows a SnackBar with [toast].
  ///
  /// Pass a [BuildContext] that's still mounted. Haptic feedback fires
  /// to match the rest of the app's interaction feel.
  static Future<void> copy({
    required BuildContext context,
    required String text,
    required String toast,
  }) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(toast),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Shares the app. Used by profile_screen.
  static Future<void> shareApp(BuildContext context) {
    return copy(
      context: context,
      text: forApp(),
      toast: 'Share message copied to clipboard',
    );
  }

  /// Shares a movie/show. Used by detail_screen.
  static Future<void> shareTitle(BuildContext context, Movie movie) {
    return copy(
      context: context,
      text: forTitle(movie),
      toast: 'Share message for "${movie.title}" copied',
    );
  }

  /// Shares a custom list.
  static Future<void> shareList(
    BuildContext context, {
    required String listTitle,
    required String listId,
  }) {
    return copy(
      context: context,
      text: forList(listTitle: listTitle, listId: listId),
      toast: 'Share message for "$listTitle" copied',
    );
  }
}