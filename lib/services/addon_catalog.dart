// Add-on catalog / meta / stream client.
//
// Fetches Stremio resource documents from installed add-ons and aggregates
// stream results across every add-on that supports the requested content.
// SPDX-License-Identifier: GPL-3.0 (ported patterns from NuvioMobile).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'addon_content_models.dart';
import 'addon_models.dart';
import 'addon_transport_urls.dart';

const _fetchTimeout = Duration(seconds: 20);

class AddonCatalogException implements Exception {
  final String message;
  const AddonCatalogException(this.message);

  @override
  String toString() => message;
}

/// Test seam for HTTP in widget-less unit tests.
typedef AddonDocumentFetcher =
    Future<String> Function(String url, {Map<String, String>? headers});

/// Stream results from one add-on (grouping key for the picker UI).
class AddonStreamGroup {
  final AddonManifest manifest;
  final List<AddonStream> streams;
  final String? errorMessage;

  const AddonStreamGroup({
    required this.manifest,
    required this.streams,
    this.errorMessage,
  });

  String get name => manifest.name;
}

// ── Public fetch API ─────────────────────────────────────────────────────────

/// Fetches one catalog page from an add-on.
Future<List<AddonCatalogItem>> fetchAddonCatalog({
  required AddonManifest manifest,
  required AddonCatalog catalog,
  Map<String, String> extra = const {},
  AddonDocumentFetcher? fetcher,
}) async {
  final base = addonTransportBaseUrl(manifest.transportUrl);
  final params = <String>[
    if (extra.isNotEmpty) Uri(queryParameters: extra).query,
    ..._queryPartsOf(manifest.transportUrl),
  ];
  final queryString = params.isEmpty ? '' : '?${params.join('&')}';
  final url = '$base/catalog/${catalog.type}/${catalog.id}.json$queryString';
  final body = await _getBody(url, fetcher: fetcher);
  return parseCatalogItems(body);
}

/// Fetches full metadata (series responses include the episode list).
Future<AddonMeta?> fetchAddonMeta({
  required AddonManifest manifest,
  required String type,
  required String id,
  AddonDocumentFetcher? fetcher,
}) async {
  final url = buildAddonResourceUrl(
    manifestUrl: manifest.transportUrl,
    resource: 'meta',
    type: type,
    id: id,
  );
  final body = await _getBody(url, fetcher: fetcher);
  return parseAddonMeta(body);
}

/// Fetches streams from a single add-on for [type]/[id] (episode ids use
/// `id:season:episode` — see [episodeStreamId]).
Future<List<AddonStream>> fetchAddonStreams({
  required AddonManifest manifest,
  required String type,
  required String id,
  Map<String, String>? headers,
  AddonDocumentFetcher? fetcher,
}) async {
  final url = buildAddonResourceUrl(
    manifestUrl: manifest.transportUrl,
    resource: 'stream',
    type: type,
    id: id,
  );
  final body = await _getBody(url, headers: headers, fetcher: fetcher);
  return parseAddonStreams(body);
}

/// Whether an add-on offers a `stream` resource usable for [type].
bool addonOffersStreams(AddonManifest manifest, String type) {
  final streamResource =
      manifest.resources.where((r) => r.name == 'stream').toList();
  if (streamResource.isEmpty) return false;
  final normalized = normalizeContentType(type);
  for (final resource in streamResource) {
    final types = resource.types.isNotEmpty ? resource.types : manifest.types;
    if (types.isEmpty ||
        types.map(normalizeContentType).any((t) => t == normalized)) {
      return true;
    }
  }
  return false;
}

/// Queries every add-on in [manifests] that supports [type] and returns the
/// per-add-on results. Individual failures are captured per group.
Future<List<AddonStreamGroup>> fetchStreamsFromAddons({
  required List<AddonManifest> manifests,
  required String type,
  required String id,
  Map<String, String>? headers,
  AddonDocumentFetcher? fetcher,
}) async {
  final applicable = manifests
      .where((m) => addonOffersStreams(m, type))
      .toList(growable: false);
  if (applicable.isEmpty) return const [];

  final results = <AddonStreamGroup>[];
  for (final manifest in applicable) {
    try {
      final streams = await fetchAddonStreams(
        manifest: manifest,
        type: type,
        id: id,
        headers: headers,
        fetcher: fetcher,
      );
      results.add(AddonStreamGroup(manifest: manifest, streams: streams));
    } catch (_) {
      results.add(AddonStreamGroup(
        manifest: manifest,
        streams: const [],
        errorMessage: 'Failed to load streams',
      ));
    }
  }
  return results;
}

// ── Internals ────────────────────────────────────────────────────────────────

Future<String> _getBody(
  String url, {
  Map<String, String>? headers,
  AddonDocumentFetcher? fetcher,
}) async {
  if (fetcher != null) return fetcher(url, headers: headers);
  final response = await http
      .get(
        Uri.parse(url),
        headers: <String, String>{'Accept': 'application/json', ...?headers},
      )
      .timeout(_fetchTimeout);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw AddonCatalogException('HTTP ${response.statusCode}');
  }
  final body = utf8.decode(response.bodyBytes);
  if (body.trim().isEmpty) {
    throw const AddonCatalogException('Empty response from server');
  }
  return body;
}

/// Raw query segments carried by a manifest transport URL (passed through to
/// every resource request, e.g. signed manifest URLs).
List<String> _queryPartsOf(String manifestUrl) {
  final idx = manifestUrl.indexOf('?');
  if (idx < 0) return const [];
  final query = manifestUrl.substring(idx + 1);
  if (query.isEmpty) return const [];
  return [query];
}
