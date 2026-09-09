// Ported from NuvioMobile's `features/addons/AddonRepository.kt`.
// SPDX-License-Identifier: GPL-3.0
// Source: https://github.com/NuvioMedia/NuvioMobile (GPL-3.0)
//
// Owns the installed-addon list: adding/removing by manifest URL, enable/
// disable, manifest (re)fetching, and local persistence via SharedPreferences.
//
// The upstream repository additionally syncs the list to the Supabase backend
// per user profile; this app is single-profile and local-first, so that layer
// is intentionally omitted here (see docs/nuvio_feature_analysis.md §6-7).
library;

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'addon_manifest_parser.dart';
import 'addon_models.dart';

/// Signature for fetching a raw manifest document. Swappable for tests.
typedef AddonFetcher = Future<String> Function(
  String url, {
  bool forceRefresh,
});

const _storagePrefix = 'feb_addons_';
const _installedUrlsKey = '${_storagePrefix}installed_urls';
const _enabledStatesKey = '${_storagePrefix}enabled_states';
const _fetchTimeout = Duration(seconds: 15);

const _defaultAddonUrls = [
  'https://torrentio.strem.fun/manifest.json',
  'https://mediafusion.elfhosted.com/manifest.json',
  'https://comet.elfhosted.com/manifest.json',
  'https://opensubtitles-pro.com/addon/manifest.json',
  'https://subsense.com/manifest.json',
];

const _defaultsInstalledKey = '${_storagePrefix}defaults_installed';

class AddonRepository extends ChangeNotifier {
  // ignore: prefer_initializing_formals — keeps the test seam param public.
  AddonRepository._({AddonFetcher? fetcher}) : _fetcher = fetcher;

  /// Global repository used by the UI.
  static final AddonRepository instance = AddonRepository._();

  /// Test seam: create an isolated repository with a custom fetcher.
  factory AddonRepository.forTesting({AddonFetcher? fetcher}) =>
      AddonRepository._(fetcher: fetcher);

  final AddonFetcher? _fetcher;

  final AddonsUiState _state = AddonsUiState(addons: <ManagedAddon>[]);
  final Map<String, Future<void>> _activeRefreshes = {};

  bool _initialized = false;
  bool _loadInProgress = false;

  AddonsUiState get state => _state;
  List<ManagedAddon> get addons => _state.addons;

  /// True once persisted addons have been loaded from disk.
  bool get isLoaded => _initialized;

  /// Installs the default preinstalled addons if not already done.
  /// Safe to call repeatedly; only runs once.
  Future<void> installDefaultAddons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyInstalled = prefs.getBool(_defaultsInstalledKey) ?? false;
      if (alreadyInstalled) return;

      for (final url in _defaultAddonUrls) {
        await addAddon(url);
      }

      await prefs.setBool(_defaultsInstalledKey, true);
    } catch (_) {}
  }

  /// Loads persisted addons and refreshes enabled manifests whose cached
  /// manifest is missing. Safe to call repeatedly.
  Future<void> ensureLoaded() async {
    if (_initialized) return;
    if (_loadInProgress) {
      // Wait for the in-flight load to finish.
      while (_loadInProgress) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return;
    }
    _loadInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUrls =
          dedupeManifestUrls(prefs.getStringList(_installedUrlsKey) ?? const []);
      final enabledByUrl = await _loadEnabledStates();
      if (storedUrls.isEmpty) return;

      final addons = <ManagedAddon>[];
      for (final url in storedUrls) {
        final enabled = enabledByUrl[url];
        addons.add(ManagedAddon(
          manifestUrl: url,
          enabled: enabled ?? true,
          isRefreshing: enabled ?? true,
        ));
      }
      _state.addons
        ..clear()
        ..addAll(addons);
      notifyListeners();

      for (final url in storedUrls) {
        if (enabledByUrl[url] ?? true) {
          refreshAddon(url);
        }
      }
    } finally {
      _loadInProgress = false;
      _initialized = true;
    }
  }

  /// Adds an addon by raw URL: normalizes it, fetches + parses its manifest,
  /// and appends it enabled. Returns a success/error result.
  Future<AddAddonResult> addAddon(String rawUrl) async {
    final String manifestUrl;
    try {
      manifestUrl = normalizeManifestUrl(rawUrl);
    } on FormatException catch (e) {
      return AddAddonError(
          e.message.isEmpty ? 'Enter an add-on URL' : e.message);
    }

    if (addons.any((a) => a.manifestUrl == manifestUrl)) {
      return const AddAddonError('Add-on already installed');
    }

    final AddonManifest manifest;
    try {
      manifest = AddonManifestParser().parse(
        manifestUrl: manifestUrl,
        payload: await _fetch(manifestUrl),
      );
    } catch (e) {
      return AddAddonError(e.toString().contains('HTTP')
          ? 'Could not load add-on manifest: $e'
          : 'Could not load add-on manifest');
    }

    _state.addons.add(ManagedAddon(
      manifestUrl: manifestUrl,
      manifest: manifest,
      enabled: true,
    ));
    notifyListeners();
    await _persist();
    return AddAddonSuccess(manifest);
  }

  void removeAddon(String manifestUrl) {
    final before = _state.addons.length;
    _state.addons.removeWhere((a) => a.manifestUrl == manifestUrl);
    if (_state.addons.length == before) return;
    notifyListeners();
    unawaited(_persist());
  }

  /// Enables or disables an installed addon. Enabling an addon whose manifest
  /// is not yet loaded triggers a refresh.
  void setAddonEnabled(String manifestUrl, bool enabled) {
    ManagedAddon? target;
    for (final addon in _state.addons) {
      if (addon.manifestUrl == manifestUrl && addon.enabled != enabled) {
        target = addon;
        break;
      }
    }
    if (target == null) return;

    final index = _state.addons.indexOf(target);
    final shouldRefresh = enabled && target.manifest == null;
    _state.addons[index] = target.copyWith(
      enabled: enabled,
      isRefreshing: shouldRefresh,
    );
    notifyListeners();
    unawaited(_persist());
    if (shouldRefresh) {
      refreshAddon(manifestUrl);
    }
  }

  /// Re-fetches every enabled addon's manifest.
  void refreshAll() {
    for (final url in addons
        .where((a) => a.enabled)
        .map((a) => a.manifestUrl)
        .toSet()) {
      refreshAddon(url, forceRefresh: true);
    }
  }

  /// Re-fetches one manifest. In-flight refreshes for the same URL are
  /// de-duplicated. The returned future completes when the refresh settles.
  Future<void> refreshAddon(String manifestUrl, {bool forceRefresh = false}) {
    final existing = _activeRefreshes[manifestUrl];
    if (existing != null) return existing;

    _markRefreshing(manifestUrl);
    final future = () async {
      try {
        final manifest = AddonManifestParser().parse(
          manifestUrl: manifestUrl,
          payload: await _fetch(manifestUrl, forceRefresh: forceRefresh),
        );
        _updateAddon(
          manifestUrl,
          (a) => a.copyWith(
            manifest: manifest,
            isRefreshing: false,
            clearError: true,
          ),
        );
      } catch (e) {
        _updateAddon(
          manifestUrl,
          (a) => a.copyWith(
            isRefreshing: false,
            errorMessage: 'Could not load add-on manifest',
          ),
        );
      } finally {
        _activeRefreshes.remove(manifestUrl);
      }
    }();
    _activeRefreshes[manifestUrl] = future;
    return future;
  }

  /// Number of enabled catalogs across enabled addons (home-row metadata).
  AddonOverview get overview => _state.overview;

  Future<String> _fetch(String url, {bool forceRefresh = false}) {
    final custom = _fetcher;
    if (custom != null) return custom(url, forceRefresh: forceRefresh);
    return _httpFetch(url, forceRefresh: forceRefresh);
  }

  static Future<String> _httpFetch(
    String url, {
    bool forceRefresh = false,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (forceRefresh) {
      headers['Cache-Control'] = 'no-cache';
    }
    final response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(_fetchTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    if (body.trim().isEmpty) {
      throw const FormatException('Empty response from server');
    }
    return body;
  }

  void _markRefreshing(String manifestUrl) {
    _updateAddon(manifestUrl, (a) => a.copyWith(isRefreshing: true));
  }

  void _updateAddon(String manifestUrl, ManagedAddon Function(ManagedAddon) fn) {
    final index = _state.addons.indexWhere((a) => a.manifestUrl == manifestUrl);
    if (index < 0) return;
    _state.addons[index] = fn(_state.addons[index]);
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _installedUrlsKey,
        dedupeManifestUrls(addons.map((a) => a.manifestUrl).toList()),
      );
      await prefs.setString(
        _enabledStatesKey,
        jsonEncode({
          for (final a in addons) a.manifestUrl: a.enabled,
        }),
      );
    } catch (_) {
      // Persistence failures are non-fatal for the session.
    }
  }

  Future<Map<String, bool>> _loadEnabledStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_enabledStatesKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return decoded.map((key, value) => MapEntry(
            ensureManifestSuffix(key),
            value == true,
          ));
    } catch (_) {
      return const {};
    }
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);

  @override
  String toString() => message;
}

/// Ensures stored URLs carry the `/manifest.json` suffix.
List<String> dedupeManifestUrls(Iterable<String> urls) =>
    urls.map(ensureManifestSuffix).toSet().toList(growable: false);

String ensureManifestSuffix(String url) {
  final path = url.split('?').first.replaceAll(RegExp(r'/+$'), '');
  final queryIndex = url.indexOf('?');
  final query = queryIndex >= 0 ? url.substring(queryIndex + 1) : '';
  final withSuffix =
      path.endsWith('/manifest.json') ? path : '$path/manifest.json';
  return query.isEmpty ? withSuffix : '$withSuffix?$query';
}

/// Mirrors Nuvio URL normalization: adds `https://` when no scheme, converts
/// `stremio://` to `https://`, strips fragments, and appends `/manifest.json`
/// while preserving any query string.
String normalizeManifestUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Enter an add-on URL');
  }

  final normalizedScheme = trimmed.startsWith('http://') ||
          trimmed.startsWith('https://')
      ? trimmed
      : trimmed.startsWith('stremio://')
          ? 'https://${trimmed.substring('stremio://'.length)}'
          : 'https://$trimmed';

  final withoutFragment = normalizedScheme.split('#').first;
  final queryIndex = withoutFragment.indexOf('?');
  final query =
      queryIndex >= 0 ? withoutFragment.substring(queryIndex + 1) : '';
  final path = (queryIndex >= 0
          ? withoutFragment.substring(0, queryIndex)
          : withoutFragment)
      .replaceAll(RegExp(r'/+$'), '');
  final manifestPath =
      path.endsWith('/manifest.json') ? path : '$path/manifest.json';

  return query.isEmpty ? manifestPath : '$manifestPath?$query';
}
