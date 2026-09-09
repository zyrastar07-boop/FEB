// Ported from NuvioMobile's `features/addons/AddonModels.kt`.
// SPDX-License-Identifier: GPL-3.0
// Source: https://github.com/NuvioMedia/NuvioMobile (GPL-3.0)
//
// Domain models for the Stremio-style addon system: a manifest describes what
// an addon can do (catalogs / meta / streams / subtitles) for which content
// types, plus transport configuration. Users install addons by manifest URL.
library;

/// Stremio addon manifest (subset used by Nuvio/FEB).
class AddonManifest {
  final String id;
  final String name;
  final String description;
  final String version;
  final String? logoUrl;
  final List<AddonResource> resources;
  final List<String> types;
  final List<String> idPrefixes;
  final List<AddonCatalog> catalogs;
  final AddonBehaviorHints behaviorHints;
  final String transportUrl;

  const AddonManifest({
    required this.id,
    required this.name,
    this.description = '',
    required this.version,
    this.logoUrl,
    this.resources = const [],
    this.types = const [],
    this.idPrefixes = const [],
    this.catalogs = const [],
    this.behaviorHints = const AddonBehaviorHints(),
    required this.transportUrl,
  });
}

class AddonResource {
  final String name;
  final List<String> types;
  final List<String> idPrefixes;

  const AddonResource({
    required this.name,
    this.types = const [],
    this.idPrefixes = const [],
  });
}

class AddonCatalog {
  final String type;
  final String id;
  final String name;
  final List<AddonExtraProperty> extra;

  const AddonCatalog({
    required this.type,
    required this.id,
    required this.name,
    this.extra = const [],
  });
}

class AddonExtraProperty {
  final String name;
  final bool isRequired;
  final List<String> options;
  final int? optionsLimit;

  const AddonExtraProperty({
    required this.name,
    this.isRequired = false,
    this.options = const [],
    this.optionsLimit,
  });
}

class AddonBehaviorHints {
  final bool configurable;
  final bool configurationRequired;
  final bool adult;
  final bool p2p;

  const AddonBehaviorHints({
    this.configurable = false,
    this.configurationRequired = false,
    this.adult = false,
    this.p2p = false,
  });
}

/// One installed addon: its manifest URL plus the last-known manifest and
/// per-install state (enabled flag, refresh/error status, optional user name).
class ManagedAddon {
  final String manifestUrl;
  final AddonManifest? manifest;
  final String? userSetName;
  final bool enabled;
  final bool isRefreshing;
  final String? errorMessage;

  const ManagedAddon({
    required this.manifestUrl,
    this.manifest,
    this.userSetName,
    this.enabled = true,
    this.isRefreshing = false,
    this.errorMessage,
  });

  bool get isActive => enabled && manifest != null;

  String get displayTitle {
    final userTitle = userSetName?.trim();
    if (userTitle != null && userTitle.isNotEmpty && userTitle != manifest?.name) {
      return userTitle;
    }
    final manifestName = manifest?.name;
    if (manifestName != null && manifestName.isNotEmpty) return manifestName;
    final withoutQuery = manifestUrl.split('?').first;
    final slash = withoutQuery.lastIndexOf('/');
    final path = slash >= 0 ? withoutQuery.substring(slash + 1) : withoutQuery;
    if (path.isNotEmpty) return path;
    return 'Add-on';
  }

  ManagedAddon copyWith({
    AddonManifest? manifest,
    String? userSetName,
    bool? enabled,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ManagedAddon(
      manifestUrl: manifestUrl,
      manifest: manifest ?? this.manifest,
      userSetName: userSetName ?? this.userSetName,
      enabled: enabled ?? this.enabled,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AddonsUiState {
  final List<ManagedAddon> addons;

  const AddonsUiState({this.addons = const []});

  AddonOverview get overview {
    var totalCatalogs = 0;
    for (final addon in addons.where((a) => a.enabled)) {
      totalCatalogs += addon.manifest?.catalogs.length ?? 0;
    }
    return AddonOverview(
      totalAddons: addons.length,
      activeAddons: addons.where((a) => a.isActive).length,
      totalCatalogs: totalCatalogs,
    );
  }

  List<ManagedAddon> get enabledAddons =>
      addons.where((a) => a.enabled).toList(growable: false);

  bool get hasPendingEnabledManifests =>
      addons.any((a) => a.enabled && a.isRefreshing);

  bool get isWaitingForFirstEnabledManifest {
    final enabled = enabledAddons;
    return enabled.isNotEmpty &&
        enabled.every((a) => a.manifest == null) &&
        enabled.any((a) => a.isRefreshing);
  }

  String? get firstEnabledManifestError {
    for (final addon in addons) {
      if (addon.enabled &&
          addon.manifest == null &&
          addon.errorMessage != null &&
          addon.errorMessage!.isNotEmpty) {
        return addon.errorMessage;
      }
    }
    return null;
  }
}

class AddonOverview {
  final int totalAddons;
  final int activeAddons;
  final int totalCatalogs;

  const AddonOverview({
    required this.totalAddons,
    required this.activeAddons,
    required this.totalCatalogs,
  });
}

sealed class AddAddonResult {
  const AddAddonResult();
}

class AddAddonSuccess extends AddAddonResult {
  final AddonManifest manifest;
  const AddAddonSuccess(this.manifest);
}

class AddAddonError extends AddAddonResult {
  final String message;
  const AddAddonError(this.message);
}
