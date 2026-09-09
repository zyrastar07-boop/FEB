// Ported from NuvioMobile's `features/addons/AddonTransportUrls.kt`.
// SPDX-License-Identifier: GPL-3.0
// Source: https://github.com/NuvioMedia/NuvioMobile (GPL-3.0)
//
// Builds the Stremio resource URLs an addon exposes once its manifest URL is
// known: `{base}/{resource}/{type}/{id}.json` (with an optional extra path
// segment for e.g. seasons) plus any query string the manifest URL carried.
library;

import 'dart:convert';

/// The addon's base transport URL: the manifest URL minus `manifest.json`.
String addonTransportBaseUrl(String manifestUrl) {
  final withoutQuery = manifestUrl.split('?').first;
  return withoutQuery.endsWith('/manifest.json')
      ? withoutQuery.substring(0, withoutQuery.length - '/manifest.json'.length)
      : withoutQuery;
}

/// Builds `{resource}/{type}/{id}.json`, e.g. `/catalog/movie/top.json`,
/// `/meta/series/tt1234.json` or `/stream/series/tt1234:1:1.json`.
String buildAddonResourceUrl({
  required String manifestUrl,
  required String resource,
  required String type,
  required String id,
  String? extraPathSegment,
}) {
  final encodedId = encodeAddonPathSegment(id);
  final baseUrl = addonTransportBaseUrl(manifestUrl);
  final query = manifestUrl.split('?').skip(1).join('?');
  final querySuffix = query.isEmpty ? '' : '?$query';
  final resourceUrl = (extraPathSegment == null || extraPathSegment.isEmpty)
      ? '$baseUrl/$resource/$type/$encodedId.json'
      : '$baseUrl/$resource/$type/$encodedId/$extraPathSegment.json';
  return '$resourceUrl$querySuffix';
}

/// Percent-encodes an id for safe use as a URL path segment, preserving
/// unreserved characters and using uppercase hex (mirrors the Kotlin port).
String encodeAddonPathSegment(String value) {
  final buffer = StringBuffer();
  const hex = '0123456789ABCDEF';
  for (final byte in utf8.encode(value)) {
    final char = String.fromCharCode(byte);
    final isUnreserved = (byte >= 0x61 && byte <= 0x7A) || // a-z
        (byte >= 0x41 && byte <= 0x5A) || // A-Z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        char == '-' ||
        char == '_' ||
        char == '.' ||
        char == '~';
    if (isUnreserved) {
      buffer.write(char);
    } else {
      buffer
        ..write('%')
        ..write(hex[(byte >> 4) & 0x0F])
        ..write(hex[byte & 0x0F]);
    }
  }
  return buffer.toString();
}
