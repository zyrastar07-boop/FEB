// Ported from NuvioMobile's `features/addons/AddonManifestParser.kt`.
// SPDX-License-Identifier: GPL-3.0
// Source: https://github.com/NuvioMedia/NuvioMobile (GPL-3.0)
//
// Parses a Stremio addon manifest document fetched from a transport URL.
library;

import 'dart:convert';

import 'addon_models.dart';

class AddonManifestParser {
  const AddonManifestParser();

  /// Parses [payload] (a JSON manifest document) that was fetched from
  /// [manifestUrl]. Relative logo URLs are resolved against the manifest URL.
  AddonManifest parse({
    required String manifestUrl,
    required String payload,
  }) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Add-on manifest must be a JSON object');
    }
    final root = decoded;

    final defaultTypes = _stringList(root, 'types');
    final defaultPrefixes = _stringList(root, 'idPrefixes');

    return AddonManifest(
      id: _requiredString(root, 'id'),
      name: _requiredString(root, 'name'),
      description: _optionalString(root, 'description') ?? '',
      version: _requiredString(root, 'version'),
      logoUrl: _resolveAgainstManifest(
        _optionalString(root, 'logo'),
        manifestUrl,
      ),
      resources: _resources(root, defaultTypes, defaultPrefixes),
      types: defaultTypes,
      idPrefixes: defaultPrefixes,
      catalogs: _catalogs(root),
      behaviorHints: _behaviorHints(root),
      transportUrl: manifestUrl,
    );
  }

  List<AddonResource> _resources(
    Map<String, dynamic> root,
    List<String> defaultTypes,
    List<String> defaultPrefixes,
  ) {
    final raw = root['resources'];
    if (raw is! List) return const [];
    final resources = <AddonResource>[];
    for (final element in raw) {
      if (element is String) {
        if (element.isNotEmpty) {
          resources.add(AddonResource(
            name: element,
            types: defaultTypes,
            idPrefixes: defaultPrefixes,
          ));
        }
      } else if (element is Map<String, dynamic>) {
        final name = _requiredString(element, 'name');
        resources.add(AddonResource(
          name: name,
          types: _stringList(element, 'types').isNotEmpty
              ? _stringList(element, 'types')
              : defaultTypes,
          idPrefixes: _stringList(element, 'idPrefixes').isNotEmpty
              ? _stringList(element, 'idPrefixes')
              : defaultPrefixes,
        ));
      }
    }
    return resources.where((r) => r.name.isNotEmpty).toList(growable: false);
  }

  List<AddonCatalog> _catalogs(Map<String, dynamic> root) {
    final raw = root['catalogs'];
    if (raw is! List) return const [];
    final catalogs = <AddonCatalog>[];
    for (final element in raw) {
      if (element is! Map<String, dynamic>) continue;
      final type = _requiredString(element, 'type');
      final id = _requiredString(element, 'id');
      catalogs.add(AddonCatalog(
        type: type,
        id: id,
        name: (_optionalString(element, 'name') ?? '').isEmpty
            ? id
            : _optionalString(element, 'name')!,
        extra: _extraProperties(element),
      ));
    }
    return catalogs;
  }

  List<AddonExtraProperty> _extraProperties(Map<String, dynamic> catalog) {
    final raw = catalog['extra'];
    if (raw is! List) return const [];
    final extras = <AddonExtraProperty>[];
    for (final element in raw) {
      if (element is! Map<String, dynamic>) continue;
      final name = _optionalString(element, 'name');
      if (name == null || name.isEmpty) continue;
      extras.add(AddonExtraProperty(
        name: name,
        isRequired: element['isRequired'] == true,
        options: _stringList(element, 'options'),
        optionsLimit: _optionalInt(element, 'optionsLimit'),
      ));
    }
    return extras;
  }

  AddonBehaviorHints _behaviorHints(Map<String, dynamic> root) {
    final hints = root['behaviorHints'];
    if (hints is! Map<String, dynamic>) {
      return const AddonBehaviorHints();
    }
    return AddonBehaviorHints(
      configurable: hints['configurable'] == true,
      configurationRequired: hints['configurationRequired'] == true,
      adult: hints['adult'] == true,
      p2p: hints['p2p'] == true,
    );
  }
}

String _requiredString(Map<String, dynamic> map, String name) {
  final value = _optionalString(map, name);
  if (value == null || value.isEmpty) {
    throw FormatException('Manifest is missing required field "$name"');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String name) {
  final value = map[name];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

List<String> _stringList(Map<String, dynamic> map, String name) {
  final value = map[name];
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

int? _optionalInt(Map<String, dynamic> map, String name) {
  final value = map[name];
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

/// Mirrors Nuvio's URL resolution: absolute/data URLs pass through, protocol-
/// relative URLs gain `https:`, root-relative URLs are joined to the manifest
/// origin, and other relative URLs are joined to the manifest directory.
String? _resolveAgainstManifest(String? url, String manifestUrl) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('data:')) {
    return url;
  }
  if (url.startsWith('//')) return 'https:$url';

  final withoutQuery = manifestUrl.split('?').first;
  // Everything up to (not including) the last '/' — the manifest directory.
  final lastSlash = withoutQuery.lastIndexOf('/');
  final manifestBase = lastSlash >= 0 ? withoutQuery.substring(0, lastSlash) : '';

  if (url.startsWith('/')) {
    // Root-relative: resolve against the manifest's scheme + host.
    final schemeEnd = manifestBase.indexOf('://');
    if (schemeEnd >= 0) {
      final scheme = manifestBase.substring(0, schemeEnd + 3);
      final hostRest = manifestBase.substring(schemeEnd + 3);
      final hostEnd = hostRest.indexOf('/');
      final origin =
          '$scheme${hostEnd >= 0 ? hostRest.substring(0, hostEnd) : hostRest}';
      return '$origin$url';
    }
    return '$manifestBase$url';
  }
  return '$manifestBase/$url';
}
