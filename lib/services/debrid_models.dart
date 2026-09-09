// Debrid provider models + registry.
//
// Ported from NuvioMobile (GPL-3.0):
//   composeApp/src/commonMain/kotlin/com/nuvio/app/features/debrid/DebridProvider.kt
//
// A *debrid* service lets a torrent stream play instantly: instead of
// downloading the torrent locally, the provider's servers fetch it, and the
// app streams a direct HTTPS link back from the provider. Only torrents that
// are already cached by the provider resolve instantly ("instant playback");
// uncached ones would queue a real transfer.
//
// SPDX-License-Identifier: GPL-3.0
library;

/// A debrid provider that the app knows how to talk to.
class DebridProvider {
  final String id;
  final String displayName;
  final String shortName;
  final bool visibleInUi;
  final Set<DebridCapability> capabilities;

  const DebridProvider({
    required this.id,
    required this.displayName,
    required this.shortName,
    this.visibleInUi = true,
    this.capabilities = const {},
  });

  bool supports(DebridCapability capability) => capabilities.contains(capability);
}

/// Things a provider can do (subset of Nuvio's model used by this app).
enum DebridCapability {
  /// Provider can turn a magnet/hash into a direct HTTPS link on demand.
  instantResolve,

  /// Provider has a personal cloud library the app could list later.
  cloudLibrary,
}

/// An API key tied to a provider (the app's stored credential).
class DebridCredential {
  final DebridProvider provider;
  final String apiKey;

  const DebridCredential({required this.provider, required this.apiKey});
}

/// Registry of supported providers (mirrors Nuvio's `DebridProviders`).
abstract final class DebridProviders {
  static const String torboxId = 'torbox';
  static const String premiumizeId = 'premiumize';
  static const String localP2pId = 'local-p2p';

  static const DebridProvider torbox = DebridProvider(
    id: torboxId,
    displayName: 'Torbox',
    shortName: 'TB',
    capabilities: {
      DebridCapability.instantResolve,
      DebridCapability.cloudLibrary,
    },
  );

  static const DebridProvider premiumize = DebridProvider(
    id: premiumizeId,
    displayName: 'Premiumize',
    shortName: 'PM',
    capabilities: {
      DebridCapability.instantResolve,
      DebridCapability.cloudLibrary,
    },
  );
  static const DebridProvider localP2p = DebridProvider(
    id: localP2pId,
    displayName: 'Local P2P',
    shortName: 'P2P',
    capabilities: {},
  );

  /// Providers the user can configure in the UI.
  static const List<DebridProvider> visible = [torbox, premiumize];

  static DebridProvider? byId(String? id) {
    final normalized = id?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final provider in visible) {
      if (provider.id == normalized) return provider;
    }
    return null;
  }

  static String displayName(String? id) => byId(id)?.displayName ?? 'Debrid';
  static String shortName(String? id) => byId(id)?.shortName ?? 'DB';

  /// Providers that have an API key stored in [apiKeys], honoring the
  /// preferred provider ordering first.
  static List<DebridCredential> configuredServices(
    Map<String, String> apiKeys, {
    String preferredId = '',
  }) {
    final byProvider = <DebridProvider, String>{};
    for (final provider in visible) {
      final key = apiKeys[provider.id]?.trim() ?? '';
      if (key.isNotEmpty) byProvider[provider] = key;
    }
    if (byProvider.isEmpty) return const [];
    final preferred = byId(preferredId);
    final ordered = <DebridProvider>[];
    if (preferred != null && byProvider.containsKey(preferred)) {
      ordered.add(preferred);
    }
    for (final provider in visible) {
      if (byProvider.containsKey(provider) && !ordered.contains(provider)) {
        ordered.add(provider);
      }
    }
    return [
      for (final provider in ordered)
        DebridCredential(provider: provider, apiKey: byProvider[provider]!),
    ];
  }
}
