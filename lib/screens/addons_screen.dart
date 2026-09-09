// Add-ons management screen.
// UI follows NuvioMobile's AddonsScreen concept (GPL-3.0):
// https://github.com/NuvioMedia/NuvioMobile
// SPDX-License-Identifier: GPL-3.0
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/tokens.dart';
import '../services/addon_models.dart';
import '../services/addon_repository.dart';
import '../services/addon_transport_urls.dart';
import '../widgets/app_card.dart';

const _gold = AppDesignTokens.goldMuted;

/// Browse, install and manage Stremio-style add-ons (catalogs, streams, meta).
class AddonsScreen extends StatefulWidget {
  const AddonsScreen({super.key});

  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen> {
  final AddonRepository _repo = AddonRepository.instance;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _repo.ensureLoaded();
  }

  Future<void> _promptAddAddon() async {
    if (_adding) return;
    final controller = TextEditingController();
    String? inlineError;

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppDesignTokens.surfaceElevated,
          title: const Text('Install add-on',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste a manifest URL (e.g. '
                  'https://example.com/manifest.json)',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'https://…/manifest.json',
                  hintStyle:
                      const TextStyle(color: Colors.white30, fontSize: 13),
                  errorText: inlineError,
                  errorStyle:
                      const TextStyle(color: AppDesignTokens.error, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) async {
                  final result = await _doAdd(controller.text);
                  if (!dialogContext.mounted) return;
                  if (result == null) return;
                  if (result is AddAddonError) {
                    setDialogState(() => inlineError = result.message);
                  } else {
                    Navigator.of(dialogContext).pop(controller.text);
                  }
                },
              ),
              if (_adding) ...[
                const SizedBox(height: 14),
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _adding
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: _adding
                  ? null
                  : () async {
                      final result = await _doAdd(controller.text);
                      if (!dialogContext.mounted) return;
                      if (result == null) return;
                      if (result is AddAddonError) {
                        setDialogState(() => inlineError = result.message);
                      } else {
                        Navigator.of(dialogContext).pop(controller.text);
                      }
                    },
              child: const Text('Install',
                  style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (url != null && url.isNotEmpty && mounted) {
      _toast('Installed add-on');
    }
  }

  Future<AddAddonResult?> _doAdd(String raw) async {
    setState(() => _adding = true);
    final result = await _repo.addAddon(raw);
    if (!mounted) return null;
    setState(() => _adding = false);
    return result;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF1F1F1F),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _openConfiguration(ManagedAddon addon) {
    final manifest = addon.manifest;
    if (manifest == null || !manifest.behaviorHints.configurable) return;
    HapticFeedback.selectionClick();
    final base = addonTransportBaseUrl(manifest.transportUrl);
    launchUrl(
      Uri.parse('$base/configure'),
      mode: LaunchMode.externalApplication,
    ).then((opened) {
      if (!opened && mounted) {
        _toast('Could not open the add-on configuration page');
      }
    });
  }

  Future<void> _confirmRemove(ManagedAddon addon) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppDesignTokens.surfaceElevated,
        title: const Text('Remove add-on?',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text('"${addon.displayTitle}" will be removed from this device.',
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove',
                style: TextStyle(
                    color: AppDesignTokens.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _repo.removeAddon(addon.manifestUrl);
      _toast('Add-on removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundCanvas,
      appBar: AppBar(
        title: const Text('Add-ons',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh all',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () {
              HapticFeedback.selectionClick();
              _repo.refreshAll();
              _toast('Refreshing add-ons…');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        onPressed: _adding ? null : _promptAddAddon,
        icon: _adding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_rounded),
        label: const Text('Add add-on',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (!_repo.isLoaded) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
            );
          }
          final addons = _repo.addons;
          if (addons.isEmpty) {
            return _EmptyState(onInstall: _promptAddAddon);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              _HeaderLine(overview: _repo.overview),
              const SizedBox(height: 10),
              for (final addon in addons) ...[
                _AddonTile(
                  addon: addon,
                  onToggle: (enabled) =>
                      _repo.setAddonEnabled(addon.manifestUrl, enabled),
                  onRefresh: () =>
                      _repo.refreshAddon(addon.manifestUrl, forceRefresh: true),
                  onRemove: () => _confirmRemove(addon),
                  onConfigure: () => _openConfiguration(addon),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderLine extends StatelessWidget {
  const _HeaderLine({required this.overview});

  final AddonOverview overview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.widgets_rounded, color: _gold, size: 14),
          const SizedBox(width: 6),
          Text(
            '${overview.activeAddons} active  ·  ${overview.totalAddons} installed'
            '${overview.totalCatalogs > 0 ? '  ·  ${overview.totalCatalogs} catalogs' : ''}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AddonTile extends StatelessWidget {
  const _AddonTile({
    required this.addon,
    required this.onToggle,
    required this.onRefresh,
    required this.onRemove,
    this.onConfigure,
  });

  final ManagedAddon addon;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final manifest = addon.manifest;
    final error = addon.errorMessage;

    return AppCard(
      borderRadius: AppDesignTokens.radiusLg,
      backgroundColor: AppDesignTokens.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _logo(manifest?.logoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(addon.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (addon.isRefreshing) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _gold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                if (error != null)
                  Text(error,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppDesignTokens.error, fontSize: 11))
                else if (manifest != null)
                  Text(manifest.description.isNotEmpty
                      ? manifest.description
                      : manifest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 11))
                else
                  Text(addon.manifestUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: addon.enabled,
            onChanged: onToggle,
            thumbColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? _gold
                    : Colors.white38),
            trackColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? _gold.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.1)),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
          PopupMenuButton<String>(
            color: AppDesignTokens.surfaceElevated,
            iconColor: Colors.white60,
            onSelected: (value) {
              switch (value) {
                case 'configure':
                  onConfigure?.call();
                case 'refresh':
                  onRefresh();
                case 'remove':
                  onRemove();
              }
            },
            itemBuilder: (_) => [
              if (addon.manifest != null &&
                  addon.manifest!.behaviorHints.configurable)
                const PopupMenuItem(
                  value: 'configure',
                  child: Text('Configure…',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              const PopupMenuItem(
                value: 'refresh',
                child: Text('Refresh manifest',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remove',
                    style: TextStyle(
                        color: AppDesignTokens.error, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _logo(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Icon(Icons.extension_rounded,
            color: _gold, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          width: 44,
          height: 44,
          color: Colors.white.withValues(alpha: 0.06),
          child: const Icon(Icons.extension_rounded,
              color: _gold, size: 22),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onInstall});

  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: const Icon(Icons.extension_rounded,
                  color: _gold, size: 34),
            ),
            const SizedBox(height: 18),
            const Text('No add-ons installed',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Add-ons bring their own catalogs and streams. Paste a '
              'manifest URL to get started — e.g. from a Stremio catalog or '
              'community add-on.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.add_rounded, color: _gold, size: 20),
              label: const Text('Install your first add-on',
                  style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
