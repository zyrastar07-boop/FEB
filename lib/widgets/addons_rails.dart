// Rails that surface installed add-ons (and their catalogs) on the Home and
// Search feeds. Both render nothing until at least one enabled add-on with
// catalogs is installed.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../screens/addon_catalog_screen.dart';
import '../services/addon_models.dart';
import '../services/addon_repository.dart';
import '../utils/adaptive.dart';

const _gold = AppDesignTokens.goldMuted;

List<AddonManifest> _catalogAddons() => AddonRepository.instance.addons
    .where((a) =>
        a.isActive && a.manifest != null && a.manifest!.catalogs.isNotEmpty)
    .map((a) => a.manifest!)
    .toList(growable: false);

/// Home feed section: one card per installed add-on with catalogs.
class AddonsHomeRail extends StatefulWidget {
  const AddonsHomeRail({super.key});

  @override
  State<AddonsHomeRail> createState() => _AddonsHomeRailState();
}

class _AddonsHomeRailState extends State<AddonsHomeRail> {
  @override
  void initState() {
    super.initState();
    AddonRepository.instance.ensureLoaded();
    AddonRepository.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    AddonRepository.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final addons = _catalogAddons();
    if (addons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: Adaptive.pagePadding(context),
          child: Row(
            children: [
              const Icon(Icons.extension_rounded,
                  size: 18, color: AppDesignTokens.gold),
              const SizedBox(width: 8),
              Text(
                'ADD-ONS',
                style: AppDesignTokens.heading.copyWith(
                  color: AppDesignTokens.textCream,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: Adaptive.pagePadding(context),
            itemCount: addons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _AddonRailCard(
              addon: addons[i],
              onTap: () => _openCatalogs(context, addons[i]),
            ),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  void _openCatalogs(BuildContext context, AddonManifest manifest) {
    HapticFeedback.selectionClick();
    showAddonCatalogPicker(context, manifest);
  }
}

/// Slim horizontal strip used at the top of the Search discovery feed.
class AddonsSearchRail extends StatefulWidget {
  const AddonsSearchRail({super.key});

  @override
  State<AddonsSearchRail> createState() => _AddonsSearchRailState();
}

class _AddonsSearchRailState extends State<AddonsSearchRail> {
  @override
  void initState() {
    super.initState();
    AddonRepository.instance.ensureLoaded();
    AddonRepository.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    AddonRepository.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final addons = _catalogAddons();
    if (addons.isEmpty) return const SizedBox.shrink();

    final pagePadding = Adaptive.pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              EdgeInsets.only(left: pagePadding.left, right: pagePadding.right),
          child: Row(
            children: [
              const Icon(Icons.extension_rounded,
                  size: 16, color: AppDesignTokens.gold),
              const SizedBox(width: 6),
              Text(
                'ADD-ON CATALOGS',
                style: AppDesignTokens.heading.copyWith(
                  color: AppDesignTokens.textCream,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: pagePadding,
            itemCount: addons.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final addon = addons[i];
              return _AddonRailCard(
                addon: addon,
                height: 96,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showAddonCatalogPicker(context, addon);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

class _AddonRailCard extends StatelessWidget {
  const _AddonRailCard({
    required this.addon,
    required this.onTap,
    this.height = 118,
  });

  final AddonManifest addon;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: height,
      child: Material(
        color: AppDesignTokens.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: AppDesignTokens.radiusLg,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDesignTokens.radiusLg,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _logo(),
                const SizedBox(height: 8),
                Text(
                  addon.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  addon.catalogs.length == 1
                      ? '1 catalog'
                      : '${addon.catalogs.length} catalogs',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    final url = addon.logoUrl;
    if (url == null || url.isEmpty) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.extension_rounded, color: _gold, size: 16),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          width: 30,
          height: 30,
          color: Colors.white.withValues(alpha: 0.06),
          child: const Icon(Icons.extension_rounded, color: _gold, size: 16),
        ),
      ),
    );
  }
}
