// Debrid accounts screen.
//
// Connects debrid services (Torbox, Premiumize) so torrent streams from
// add-ons can resolve to instant direct HTTPS links for playback and
// downloads. Modeled on NuvioMobile's debrid settings screens (GPL-3.0).
//
// SPDX-License-Identifier: GPL-3.0
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../design/tokens.dart';
import '../services/debrid_models.dart';
import '../services/debrid_settings.dart';

const _gold = AppDesignTokens.gold;

class DebridScreen extends StatefulWidget {
  const DebridScreen({super.key});

  @override
  State<DebridScreen> createState() => _DebridScreenState();
}

class _DebridScreenState extends State<DebridScreen> {
  final Map<String, TextEditingController> _keyControllers = {};
  bool _loading = true;
  bool _validatingProvider = false;

  DebridSettings get _settings => DebridSettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _init();
  }

  Future<void> _init() async {
    await _settings.ensureLoaded();
    for (final provider in DebridProviders.visible) {
      final existing = _settings.apiKeyFor(provider.id);
      _keyControllers[provider.id] =
          TextEditingController(text: existing);
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Validates a key against the provider's account endpoint and persists it
  /// when valid. Returns a user-facing message.
  Future<String?> _saveAndValidate(DebridProvider provider) async {
    final controller = _keyControllers[provider.id]!;
    final key = controller.text.trim();
    if (key.isEmpty) {
      await _settings.setApiKey(provider.id, '');
      return '${provider.displayName} key removed.';
    }
    setState(() => _validatingProvider = true);
    try {
      final valid = await _validateKey(provider, key);
      if (!valid) return 'That key was rejected by ${provider.displayName}.';
      await _settings.setApiKey(provider.id, key);
      return '${provider.displayName} connected ✓';
    } catch (_) {
      return 'Could not reach ${provider.displayName}. Try again.';
    } finally {
      if (mounted) setState(() => _validatingProvider = false);
    }
  }

  Future<bool> _validateKey(DebridProvider provider, String key) async {
    final httpClient = http.Client();
    try {
      final headers = {
        'Authorization': 'Bearer $key',
        'Accept': 'application/json',
      };
      final response = switch (provider.id) {
        DebridProviders.torboxId => await httpClient.get(
            Uri.parse('https://api.torbox.app/v1/api/user/me'),
            headers: headers,
          ),
        DebridProviders.premiumizeId => await httpClient.get(
            Uri.parse('https://www.premiumize.me/api/account/info'),
            headers: headers,
          ),
        _ => null,
      };
      if (response == null) return false;
      if (response.statusCode == 401 || response.statusCode == 403) {
        return false;
      }
      return response.statusCode >= 200 && response.statusCode < 300;
    } finally {
      httpClient.close();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: Colors.black87,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundCanvas,
      appBar: AppBar(
        backgroundColor: AppDesignTokens.backgroundCanvas,
        title: const Text('Debrid',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: _gold))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _explainer(),
                const SizedBox(height: 14),
                _masterSwitch(),
                const SizedBox(height: 14),
                for (final provider in DebridProviders.visible) ...[
                  _providerCard(provider),
                  const SizedBox(height: 12),
                ],
                if (_settings.configuredServices.length > 1) ...[
                  const SizedBox(height: 4),
                  _preferredSelector(),
                ],
                const SizedBox(height: 12),
                Text(
                  'Keys are stored locally on this device only. '
                  'Instant resolve works only for torrents the service has '
                  'already cached.',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 11.5, height: 1.5),
                ),
              ],
            ),
    );
  }

  Widget _explainer() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt_rounded, color: _gold, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Debrid makes torrent streams from add-ons play instantly. '
              'Connect an account below, then tap a torrent stream in any '
              'add-on and it will resolve to a direct link.',
              style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _masterSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: _gold,
        title: const Text('Instant debrid playback',
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: const Text(
          'Resolve torrent streams via a connected provider',
          style: TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
        value: _settings.enabled,
        onChanged: _settings.setEnabled,
      ),
    );
  }

  Widget _providerCard(DebridProvider provider) {
    final controller = _keyControllers[provider.id];
    final hasKey = (_settings.apiKeyFor(provider.id)).isNotEmpty;
    final validating = _validatingProvider;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasKey
              ? _gold.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(provider.shortName,
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 8),
              Text(provider.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (hasKey)
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 16),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            obscureText: true,
            enabled: !validating,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Paste ${provider.displayName} API key',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.5),
              isDense: true,
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.25),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _gold, width: 1),
              ),
              suffixIcon: validating
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _gold),
                      ),
                    )
                  : null,
            ),
            onSubmitted: (_) => _submitKey(provider),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: _gold.withValues(alpha: 0.14),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: validating ? null : () => _submitKey(provider),
              child: Text(
                hasKey ? 'Update key' : 'Connect',
                style: const TextStyle(
                    color: _gold,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitKey(DebridProvider provider) async {
    HapticFeedback.selectionClick();
    final message = await _saveAndValidate(provider);
    if (!mounted) return;
    _toast(message ?? 'Saved.');
  }

  Widget _preferredSelector() {
    final services = _settings.configuredServices;
    final active = _settings.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PREFERRED PROVIDER',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              for (final service in services)
                _preferredRow(service, enabled: active),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preferredRow(DebridCredential service, {required bool enabled}) {
    final selected =
        _settings.preferredService?.provider.id == service.provider.id;
    return InkWell(
      onTap: enabled
          ? () => _settings.setPreferredProvider(service.provider.id)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected && enabled ? _gold : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(service.provider.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            Text(service.provider.shortName,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
