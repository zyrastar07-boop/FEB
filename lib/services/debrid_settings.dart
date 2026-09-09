// Debrid settings (API keys, enabled state, preferred provider).
//
// Settings live in SharedPreferences under the `feb_debrid_` prefix and are
// exposed through a ChangeNotifier singleton so the player, download picker
// and settings UI can react to changes.
//
// SPDX-License-Identifier: GPL-3.0
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debrid_models.dart';

class DebridSettings extends ChangeNotifier {
  DebridSettings._();
  static final DebridSettings instance = DebridSettings._();

  static const _prefix = 'feb_debrid_';

  bool _enabled = false;
  String _preferredProviderId = '';
  final Map<String, String> _apiKeys = {};
  bool _loaded = false;
  Future<void>? _loading;

  bool get enabled => _enabled;
  String get preferredProviderId => _preferredProviderId;

  bool get hasConfiguredProvider =>
      DebridProviders.configuredServices(_apiKeys,
              preferredId: _preferredProviderId)
          .isNotEmpty;

  /// Providers with keys, preferred first — the order instant resolution
  /// tries them in.
  List<DebridCredential> get configuredServices =>
      DebridProviders.configuredServices(_apiKeys,
          preferredId: _preferredProviderId);

  DebridCredential? get preferredService =>
      configuredServices.isEmpty ? null : configuredServices.first;

  String apiKeyFor(String providerId) =>
      _apiKeys[providerId.trim().toLowerCase()] ?? '';

  /// Loads persisted settings exactly once; subsequent calls return the
  /// same in-flight future. Safe to call from any async entry point.
  Future<void> ensureLoaded() {
    final pending = _loading;
    if (pending != null) return pending;
    if (_loaded) return Future.value();
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _enabled = p.getBool('${_prefix}enabled') ?? false;
      _preferredProviderId =
          p.getString('${_prefix}preferredProvider') ?? '';
      for (final provider in DebridProviders.visible) {
        final key = p.getString('${_prefix}key_${provider.id}');
        if (key != null && key.trim().isNotEmpty) {
          _apiKeys[provider.id] = key.trim();
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('${_prefix}enabled', value);
    } catch (_) {}
  }

  /// Stores (or clears, when [apiKey] is blank) a provider's API key.
  Future<void> setApiKey(String providerId, String apiKey) async {
    final id = providerId.trim().toLowerCase();
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      _apiKeys.remove(id);
    } else {
      _apiKeys[id] = trimmed;
    }
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      if (trimmed.isEmpty) {
        await p.remove('${_prefix}key_$id');
      } else {
        await p.setString('${_prefix}key_$id', trimmed);
      }
    } catch (_) {}
  }

  Future<void> setPreferredProvider(String providerId) async {
    _preferredProviderId = providerId.trim().toLowerCase();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('${_prefix}preferredProvider', _preferredProviderId);
    } catch (_) {}
  }
}
