// Add-on catalog browsing: fetches one catalog page from an installed add-on
// and presents it as a poster grid. When the catalog declares `extra`
// properties with options (genre, search, …) they become filter chips that
// re-query the add-on. Tapping a title opens the add-on detail screen.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../services/addon_catalog.dart';
import '../services/addon_content_models.dart';
import '../services/addon_models.dart';
import 'addon_detail_screen.dart';

const _gold = AppDesignTokens.goldMuted;
const _bg = AppDesignTokens.backgroundCanvas;

/// Bottom sheet listing an add-on's catalogs; tapping one opens [AddonCatalogScreen].
Future<void> showAddonCatalogPicker(
  BuildContext context,
  AddonManifest manifest,
) async {
  if (manifest.catalogs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('This add-on does not expose any catalogs'),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppDesignTokens.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              manifest.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final catalog in manifest.catalogs)
                  ListTile(
                    leading: Icon(
                      catalog.type == 'movie'
                          ? Icons.movie_outlined
                          : Icons.live_tv_outlined,
                      color: _gold,
                      size: 22,
                    ),
                    title: Text(
                      catalog.name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      catalog.type,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white38, size: 20),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AddonCatalogScreen(
                          manifest: manifest,
                          catalog: catalog,
                        ),
                      ));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Grid of one add-on catalog, with optional extra-property filters.
class AddonCatalogScreen extends StatefulWidget {
  final AddonManifest manifest;
  final AddonCatalog catalog;

  const AddonCatalogScreen({
    super.key,
    required this.manifest,
    required this.catalog,
  });

  @override
  State<AddonCatalogScreen> createState() => _AddonCatalogScreenState();
}

class _AddonCatalogScreenState extends State<AddonCatalogScreen> {
  List<AddonCatalogItem>? _items;
  String? _error;
  bool _loading = true;

  /// Currently selected value per extra property name (genre, …).
  final Map<String, String> _selectedExtra = {};

  List<AddonExtraProperty> get _filterableExtras =>
      widget.catalog.extra.where((e) => e.options.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _extraParams() {
    final params = <String, String>{};
    for (final extra in widget.catalog.extra) {
      final value = _selectedExtra[extra.name];
      if (value != null && value.isNotEmpty) params[extra.name] = value;
    }
    return params;
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await fetchAddonCatalog(
        manifest: widget.manifest,
        catalog: widget.catalog,
        extra: _extraParams(),
      );
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this catalog.\nCheck the add-on URL and try again.';
      });
    }
  }

  int _loadRequestId = 0;

  void _toggleExtra(AddonExtraProperty extra, String option) {
    HapticFeedback.selectionClick();
    final current = _selectedExtra[extra.name];
    setState(() {
      if (current == option) {
        _selectedExtra.remove(extra.name);
      } else {
        _selectedExtra[extra.name] = option;
      }
    });
    _load();
  }

  void _openItem(AddonCatalogItem item) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AddonDetailScreen(
        manifest: widget.manifest,
        item: item,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.catalog.name.isEmpty
        ? widget.manifest.name
        : widget.catalog.name;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white38, size: 40),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13, height: 1.5)),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, color: _gold, size: 18),
                label: const Text('Retry',
                    style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final items = _items ?? const <AddonCatalogItem>[];
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_alt_off_rounded,
                  color: Colors.white30, size: 36),
              const SizedBox(height: 12),
              const Text('No titles match this selection',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              if (_selectedExtra.isNotEmpty) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () {
                    setState(_selectedExtra.clear);
                    _load();
                  },
                  child: const Text('Clear filters',
                      style: TextStyle(color: _gold, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_filterableExtras.isNotEmpty) _buildFilterStrip(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  (constraints.maxWidth / 150).clamp(2, 6).floor();
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.52,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) => _CatalogPoster(
                  item: items[index],
                  onTap: () => _openItem(items[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterStrip() {
    final extras = _filterableExtras;
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < extras.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                _extraFilterGroup(extras[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _extraFilterGroup(AddonExtraProperty extra) {
    final selected = _selectedExtra[extra.name];
    return Row(
      children: [
        if (extra.name.isNotEmpty) ...[
          Text(
            '${extra.name.toUpperCase()}:',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
        ],
        for (final option in extra.options)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(option,
                  style: TextStyle(
                      color: selected == option ? Colors.black : Colors.white,
                      fontSize: 11.5)),
              selected: selected == option,
              onSelected: (_) => _toggleExtra(extra, option),
              selectedColor: _gold,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              side: BorderSide(
                color: selected == option
                    ? Colors.transparent
                    : Colors.white12,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
      ],
    );
  }
}

class _CatalogPoster extends StatelessWidget {
  const _CatalogPoster({required this.item, required this.onTap});

  final AddonCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final poster = item.poster;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: AppDesignTokens.radiusLg,
              child: poster == null || poster.isEmpty
                  ? Container(
                      color: Colors.white.withValues(alpha: 0.06),
                      alignment: Alignment.center,
                      child: const Icon(Icons.movie_outlined,
                          color: Colors.white30, size: 28),
                    )
                  : CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: Colors.white.withValues(alpha: 0.06),
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white30, size: 24),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, height: 1.2),
          ),
          if (item.releaseInfo != null && item.releaseInfo!.isNotEmpty)
            Text(
              item.releaseInfo!,
              style:
                  const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
        ],
      ),
    );
  }
}
